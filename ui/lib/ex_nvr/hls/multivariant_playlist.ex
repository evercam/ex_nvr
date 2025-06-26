defmodule ExNVR.HLS.MultivariantPlaylist do
  @moduledoc false

  alias ExM3U8.{MultivariantPlaylist, Tags}
  alias ExNVR.HLS.MediaPlaylist

  @type t :: %__MODULE__{
          streams: %{variant() => Tags.Stream.t()},
          playlists: %{variant() => MediaPlaylist.t()}
        }

  defstruct streams: %{}, playlists: %{}

  @type tags :: Tags.Segment.t() | Tags.MediaInit.t() | Tags.Discontinuity.t()
  @type variant :: atom()

  @spec new(Keyword.t()) :: t()
  def new(_opts) do
    %__MODULE__{}
  end

  @spec add_variant(t(), variant()) :: t()
  def add_variant(%__MODULE__{streams: streams} = state, variant) do
    streams =
      Map.put(streams, variant, %Tags.Stream{
        uri: "#{variant}.m3u8",
        bandwidth: 0,
        codecs: ""
      })

    playlists = Map.put(state.playlists, variant, MediaPlaylist.new([]))

    %__MODULE__{state | streams: streams, playlists: playlists}
  end

  @spec update_settings(t(), variant(), Keyword.t()) :: t()
  def update_settings(%__MODULE__{streams: streams} = state, variant, settings) do
    stream = %{streams[variant] | codecs: settings[:codecs], resolution: settings[:resolution]}
    %{state | streams: Map.put(streams, variant, stream)}
  end

  @spec count_segments(t(), variant()) :: non_neg_integer()
  def count_segments(%__MODULE__{playlists: playlists}, variant) do
    playlists[variant].total_segments
  end

  @spec add_init_header(t(), variant(), String.t()) :: t()
  def add_init_header(%__MODULE__{} = state, variant, uri) do
    playlist = MediaPlaylist.add_init_header(state.playlists[variant], uri)
    %{state | playlists: Map.put(state.playlists, variant, playlist)}
  end

  @spec add_segment(t(), variant(), MediaPlaylist.segment()) :: {t(), [tags()]}
  def add_segment(%__MODULE__{} = state, variant, segment) do
    {playlist, discarded} = MediaPlaylist.add_segment(state.playlists[variant], segment)

    streams =
      Map.update!(state.streams, variant, &%{&1 | bandwidth: max(&1.bandwidth, segment.bitrate)})

    state = %{
      state
      | playlists: Map.put(state.playlists, variant, playlist),
        streams: streams
    }

    {state, discarded}
  end

  @spec add_discontinuity(t(), variant()) :: t()
  def add_discontinuity(%__MODULE__{} = state, variant) do
    playlist = MediaPlaylist.add_discontinuity(state.playlists[variant])
    %{state | playlists: Map.put(state.playlists, variant, playlist)}
  end

  @spec serialize(t()) :: {String.t(), %{variant() => String.t()}}
  def serialize(%__MODULE__{} = state) do
    master =
      %MultivariantPlaylist{independent_segments: true, items: Map.values(state.streams)}
      |> ExM3U8.serialize()

    playlists =
      Map.new(state.playlists, fn {name, playlist} ->
        {name, MediaPlaylist.serialize(playlist)}
      end)

    {master, playlists}
  end
end
