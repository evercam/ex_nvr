defmodule ExNVR.Media.Track do
  @moduledoc """
  A module describing a track.

  A track may be of type `video`, `audio` or `application` (carrying metadata about a stream).
  It's used mainly to signal available streams between the different elements of a pipeline
  """

  @type t :: %__MODULE__{
          type: :audio | :video | :application,
          encoding: atom(),
          rtpmap: map(),
          fmtp: map()
        }

  @enforce_keys [:type]
  defstruct @enforce_keys ++ [encoding: nil, rtpmap: nil, fmtp: nil]

  @spec new(atom(), atom(), map(), map()) :: t()
  def new(type, encoding, rtpmap, fmtp) do
    %__MODULE__{
      type: type,
      encoding: encoding,
      rtpmap: rtpmap,
      fmtp: fmtp
    }
  end
end
