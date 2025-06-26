defmodule ExNVR.HLS.MediaPlaylist do
  @moduledoc false

  @type t :: %__MODULE__{
          playlist: ExM3U8.MediaPlaylist.t(),
          total_segments: non_neg_integer(),
          target_window_duration: non_neg_integer() | nil
        }

  defstruct playlist: nil, total_segments: 0, target_window_duration: nil

  alias ExM3U8.{MediaPlaylist, Tags}

  @type segment :: %{uri: String.t(), duration: number()}
  @type tags :: Tags.Segment.t() | Tags.MediaInit.t() | Tags.Discontinuity.t()

  @spec new(Keyword.t()) :: t()
  def new(opts) do
    playlist = %MediaPlaylist{
      timeline: [],
      info: %MediaPlaylist.Info{
        version: 7,
        independent_segments: Keyword.get(opts, :independant_segments, true),
        media_sequence: 0,
        discontinuity_sequence: 0,
        target_duration: 0
      }
    }

    %__MODULE__{
      playlist: playlist,
      target_window_duration: Keyword.get(opts, :target_window_duration, 60)
    }
  end

  @spec add_init_header(t(), String.t()) :: t()
  def add_init_header(%__MODULE__{playlist: playlist} = state, uri) do
    new_playlist = %MediaPlaylist{
      playlist
      | timeline: [%Tags.MediaInit{uri: uri} | playlist.timeline]
    }

    %{state | playlist: new_playlist}
  end

  @spec add_segment(t(), segment()) :: {t(), [tags()]}
  def add_segment(%__MODULE__{playlist: playlist} = state, segment) do
    {playlist, discarded} =
      playlist
      |> do_add_segment(segment)
      |> delete_old_segments(state.target_window_duration)

    {%{state | playlist: playlist, total_segments: state.total_segments + 1}, discarded}
  end

  @spec add_discontinuity(t()) :: t()
  def add_discontinuity(%__MODULE__{playlist: playlist} = state) do
    new_playlist = %MediaPlaylist{
      playlist
      | timeline: [%Tags.Discontinuity{} | playlist.timeline]
    }

    %{state | playlist: new_playlist}
  end

  @spec serialize(t()) :: String.t()
  def serialize(%__MODULE__{playlist: playlist}) do
    ExM3U8.serialize(%{playlist | timeline: Enum.reverse(playlist.timeline)})
  end

  defp do_add_segment(playlist, segment) do
    %MediaPlaylist{
      playlist
      | timeline: [
          %Tags.Segment{uri: segment.uri, duration: segment.duration} | playlist.timeline
        ],
        info: %MediaPlaylist.Info{
          playlist.info
          | target_duration: max(playlist.info.target_duration, round(segment.duration))
        }
    }
  end

  defp delete_old_segments(playlist, max_duration) do
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

    frequencies =
      Enum.frequencies_by(discard, fn
        %Tags.Segment{} -> :segment
        %Tags.Discontinuity{} -> :discontinuity
        _ -> :other
      end)

    playlist = %{
      playlist
      | timeline: Enum.reverse(timeline),
        info: %{
          playlist.info
          | media_sequence: playlist.info.media_sequence + (frequencies[:segment] || 0),
            discontinuity_sequence:
              playlist.info.discontinuity_sequence + (frequencies[:discontinuity] || 0)
        }
    }

    {playlist, Enum.reverse(discard)}
  end

  defp maybe_discard_tag(%Tags.MediaInit{} = init, acc) do
    case acc do
      {[%Tags.MediaInit{} | _rest] = timeline, discard, duration} ->
        {timeline, [init | discard], duration}

      {timeline, discard, duration} ->
        {[init | timeline], discard, duration}
    end
  end

  defp maybe_discard_tag(tag, {timeline, discard, duration}) do
    {timeline, [tag | discard], duration}
  end
end
