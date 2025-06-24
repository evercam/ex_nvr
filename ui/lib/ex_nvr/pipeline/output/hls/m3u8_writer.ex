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
    GenServer.call(pid, {:update_playlist_settings, variant, settings})
  end

  def add_init_header(pid, variant \\ nil, uri) do
    GenServer.call(pid, {:add_init_header, variant, uri})
  end

  def add_segment(pid, variant, segment) do
    GenServer.call(pid, {:add_segment, variant, segment})
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

    {:reply, :ok, %{state | playlists: playlists, streams: streams}}
  end

  @impl true
  def handle_call({:add_init_header, variant, uri}, _from, state) do
    playlist = Map.get(state.playlists, variant || :default)

    updated_playlist = %{
      playlist
      | timeline: [%Tags.MediaInit{uri: uri} | playlist.timeline]
    }

    playlists = Map.put(state.playlists, variant || :default, updated_playlist)

    {:reply, :ok, %{state | playlists: playlists}}
  end

  @impl true
  def handle_call(
        {:update_playlist_settings, variant, settings},
        _from,
        %{playlist_type: :multivariant} = state
      ) do
    stream = %{
      Map.get(state.streams, variant)
      | codecs: settings[:codecs],
        resolution: settings[:resolution]
    }

    {:reply, :ok, put_in(state, [:streams, variant], stream)}
  end

  @impl true
  def handle_call({:add_segment, variant, {uri, duration, bitrate}}, _from, state) do
    playlist =
      state.playlists
      |> Map.get(variant || :default)
      |> add_segment_to_playlist(uri, duration)
      |> delete_old_segments(state.target_window_duration, state.location)

    state = put_in(state, [:playlists, variant || :default], playlist)
    state = update_bandwidth(state, variant, bitrate)
    {:reply, :ok, serialize(state)}
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
    stream = state.streams[variant || :default]
    stream = %{stream | bandwidth: max(stream.bandwidth, bitrate)}
    put_in(state, [:streams, variant || :default], stream)
  end

  defp delete_old_segments(playlist, max_duration, dir) do
    {timeline, to_delete, _duration} =
      Enum.reduce(playlist.timeline, {[], [], 0}, fn
        %Tags.Segment{} = seg, {timeline, to_delete, duration} when duration >= max_duration ->
          {timeline, [seg | to_delete], duration}

        %Tags.Segment{} = seg, {timeline, to_delete, duration} ->
          {[seg | timeline], to_delete, duration + seg.duration}

        element, {timeline, to_delete, duration} ->
          {[element | timeline], to_delete, duration}
      end)

    :ok = Enum.each(to_delete, &File.rm!(Path.join(dir, &1.uri)))

    %{
      playlist
      | timeline: Enum.reverse(timeline),
        info: %{playlist.info | media_sequence: playlist.info.media_sequence + length(to_delete)}
    }
  end

  defp serialize(%{playlist_type: :multivariant} = state) do
    %MultivariantPlaylist{independent_segments: true, items: Map.values(state.streams)}
    |> ExM3U8.serialize()
    |> then(&File.write!(Path.join(state.location, "index.m3u8"), &1))

    Enum.each(state.playlists, fn {variant, playlist} ->
      path = Path.join(state.location, "#{variant}.m3u8")

      playlist
      |> Map.update!(:timeline, &Enum.reverse/1)
      |> ExM3U8.serialize()
      |> then(&File.write!(path, &1))
    end)

    state
  end
end
