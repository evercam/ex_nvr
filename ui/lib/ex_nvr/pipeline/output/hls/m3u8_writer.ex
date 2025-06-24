defmodule ExNVR.Pipeline.Output.HLS.M3U8Writer do
  @moduledoc false

  use GenServer

  alias ExM3U8.{MediaPlaylist, MultivariantPlaylist, Tags}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def add_playlist(pid, playlist_name) do
    GenServer.call(pid, {:add_playlist, playlist_name})
  end

  def update_playlist_settings(pid, variant, settings) do
    GenServer.cast(pid, {:update_playlist_settings, variant, settings})
  end

  def add_init_header(pid, variant \\ nil, uri) do
    GenServer.cast(pid, {:add_init_header, variant, uri})
  end

  def add_segment(pid, variant, segment) do
    GenServer.cast(pid, {:add_segment, variant, segment})
  end

  def add_discontinuity(pid, variant) do
    GenServer.cast(pid, {:discontinuity, variant})
  end

  def total_segments(pid, variant) do
    GenServer.call(pid, {:total_segments, variant})
  end

  @impl true
  def init(opts) do
    playlist_type = Keyword.get(opts, :playlist_type, :media)

    state = %{
      playlist_type: playlist_type,
      playlists: %{},
      streams: %{},
      location: opts[:location],
      target_window_duration: opts[:target_window_duration] || 60,
      total_segments: %{}
    }

    case playlist_type do
      :multivariant ->
        {:ok, state}

      :media ->
        playlists = %{default: new_playlist()}
        {:ok, %{state | playlists: playlists}}
    end
  end

  @impl true
  def handle_call({:add_playlist, name}, _from, %{playlist_type: :multivariant} = state) do
    playlists = Map.put(state.playlists, name, new_playlist())

    streams =
      Map.put(state.streams, name, %ExM3U8.Tags.Stream{
        uri: "#{name}.m3u8",
        bandwidth: 0,
        codecs: ""
      })

    total_segments = Map.put(state.total_segments, name, 0)

    {:reply, :ok,
     %{state | playlists: playlists, streams: streams, total_segments: total_segments}}
  end

  @impl true
  def handle_call({:total_segments, variant}, _from, state) do
    {:reply, state.total_segments[variant_name(state, variant)], state}
  end

  @impl true
  def handle_cast({:add_init_header, variant, uri}, state) do
    variant = variant_name(state, variant)
    playlist = Map.get(state.playlists, variant)

    updated_playlist = %{
      playlist
      | timeline: [%Tags.MediaInit{uri: uri} | playlist.timeline]
    }

    playlists = Map.put(state.playlists, variant, updated_playlist)

    {:noreply, %{state | playlists: playlists}}
  end

  @impl true
  def handle_cast(
        {:update_playlist_settings, variant, settings},
        %{playlist_type: :multivariant} = state
      ) do
    stream = %{
      Map.get(state.streams, variant)
      | codecs: settings[:codecs],
        resolution: settings[:resolution]
    }

    {:noreply, put_in(state, [:streams, variant], stream)}
  end

  @impl true
  def handle_cast({:add_segment, variant, {uri, duration, bitrate}}, state) do
    variant = variant_name(state, variant)

    playlist =
      state.playlists
      |> Map.get(variant)
      |> add_segment_to_playlist(uri, duration)
      |> delete_old_segments(state.target_window_duration, state.location)

    total_segments = Map.update!(state.total_segments, variant, &(&1 + 1))
    playlists = Map.put(state.playlists, variant, playlist)

    state = %{state | playlists: playlists, total_segments: total_segments}
    state = update_bandwidth(state, variant, bitrate)
    {:noreply, serialize(state)}
  end

  @impl true
  def handle_cast({:discontinuity, variant}, state) do
    variant = variant_name(state, variant)
    playlist = state.playlists[variant]
    playlist = %{playlist | timeline: [%Tags.Discontinuity{} | playlist.timeline]}
    {:noreply, put_in(state, [:playlists, variant], playlist)}
  end

  defp new_playlist() do
    %MediaPlaylist{
      timeline: [],
      info: %MediaPlaylist.Info{
        version: 7,
        independent_segments: true,
        media_sequence: 0,
        discontinuity_sequence: 0,
        target_duration: 0
      }
    }
  end

  defp add_segment_to_playlist(playlist, uri, duration) do
    %{
      playlist
      | timeline: [%Tags.Segment{uri: uri, duration: duration} | playlist.timeline],
        info: %MediaPlaylist.Info{
          playlist.info
          | target_duration: max(playlist.info.target_duration, ceil(duration))
        }
    }
  end

  defp update_bandwidth(%{playlist_type: :multivariant} = state, variant, bitrate) do
    variant = variant_name(state, variant)
    stream = state.streams[variant]
    stream = %{stream | bandwidth: max(stream.bandwidth, bitrate)}
    put_in(state, [:streams, variant], stream)
  end

  defp delete_old_segments(playlist, max_duration, dir) do
    {timeline, discard, _duration} =
      Enum.reduce(playlist.timeline, {[], [], 0}, fn tag, {timeline, discard, duration} = acc ->
        cond do
          duration >= max_duration ->
            maybe_discard_tag(tag, acc)

          is_struct(tag, Tags.Segment) ->
            duration = duration + tag.duration
            {[tag | timeline], discard, duration}

          true ->
            {[tag | timeline], discard, duration}
        end
      end)

    {seg_count, disc_count} =
      Enum.reduce(discard, {0, 0}, fn
        %Tags.Segment{uri: uri}, {seg_count, disc_count} ->
          File.rm!(Path.join(dir, uri))
          {seg_count + 1, disc_count}

        %Tags.Discontinuity{}, {seg_count, disc_count} ->
          {seg_count, disc_count + 1}

        _tag, acc ->
          acc
      end)

    %{
      playlist
      | timeline: Enum.reverse(timeline),
        info: %{
          playlist.info
          | media_sequence: playlist.info.media_sequence + seg_count,
            discontinuity_sequence: playlist.info.discontinuity_sequence + disc_count
        }
    }
  end

  defp serialize(state) do
    if state.playlist_type == :multivariant do
      %MultivariantPlaylist{independent_segments: true, items: Map.values(state.streams)}
      |> ExM3U8.serialize()
      |> then(&File.write!(Path.join(state.location, "index.m3u8"), &1))
    end

    Enum.each(state.playlists, fn {variant, playlist} ->
      path = Path.join(state.location, "#{variant}.m3u8")

      playlist
      |> Map.update!(:timeline, &Enum.reverse/1)
      |> ExM3U8.serialize()
      |> then(&File.write!(path, &1))
    end)

    state
  end

  defp maybe_discard_tag(%Tags.MediaInit{} = init, acc) do
    case acc do
      {[%Tags.MediaInit{} | _rest], _, _} = acc -> acc
      {timeline, discard, duration} -> {[init | timeline], discard, duration}
    end
  end

  defp maybe_discard_tag(tag, {timeline, discard, duration}) do
    {timeline, [tag | discard], duration}
  end

  defp variant_name(%{playlist_type: :multivariant}, variant), do: variant
  defp variant_name(_state, _variant), do: :default
end
