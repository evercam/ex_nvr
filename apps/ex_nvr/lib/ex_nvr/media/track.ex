defmodule ExNVR.Media.Track do
  @moduledoc """
  A module describing a track.

  A track may be of type `video`, `audio` or `application` (carrying metadata about a stream).
  It's used mainly to signal available streams between the different elements of a pipeline
  """

  @type media_type :: :application | :audio | :video
  @type media_codec :: atom()

  @type t :: %__MODULE__{
          type: media_type(),
          encoding: media_codec(),
          total_bytes: non_neg_integer(),
          avg_bitrate: non_neg_integer(),
          # video properties
          profile: atom(),
          resolution: {non_neg_integer(), non_neg_integer()},
          total_frames: non_neg_integer(),
          avg_fps: number(),
          avg_gop_size: number(),
          gop_size: non_neg_integer()
        }

  @enforce_keys [:type]
  defstruct @enforce_keys ++
              [
                encoding: nil,
                total_bytes: 0,
                avg_bitrate: 0,
                profile: nil,
                resolution: nil,
                total_frames: 0,
                avg_fps: 0,
                avg_gop_size: 0.0,
                gop_size: 0
              ]

  @spec new(media_type(), media_codec()) :: t()
  def new(type, encoding) do
    encoding = if is_binary(encoding), do: String.to_existing_atom(encoding), else: encoding
    %__MODULE__{type: type, encoding: encoding}
  end
end
