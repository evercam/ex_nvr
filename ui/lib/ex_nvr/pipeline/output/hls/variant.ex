defmodule ExNVR.Pipeline.Output.HLS.Variant do
  @moduledoc """
  Struct describing a variant in an HLS playlist.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          writer: ExMP4.FWriter.t() | nil,
          last_buffer: Membrane.Buffer.t() | nil,
          track: ExMP4.Track.t() | nil,
          segment_duration: non_neg_integer(),
          playable?: boolean(),
          count_segments: non_neg_integer(),
          count_media_init: non_neg_integer(),
          insert_discontinuity?: boolean()
        }

  defstruct name: nil,
            writer: nil,
            last_buffer: nil,
            track: nil,
            segment_duration: 0,
            playable?: false,
            count_segments: 0,
            count_media_init: 0,
            insert_discontinuity?: false

  def new(name) do
    %__MODULE__{name: name}
  end

  def inc_segment_count(%__MODULE__{count_segments: count} = stream) do
    %{stream | count_segments: count + 1}
  end

  def inc_media_init_count(%__MODULE__{count_media_init: count} = stream) do
    %{stream | count_media_init: count + 1}
  end

  def reset_writer(%__MODULE__{} = stream) do
    %{stream | writer: nil, last_buffer: nil, segment_duration: 0, track: nil}
  end
end
