defmodule ExNVR.Pipeline.Track do
  @moduledoc """
  A module describing a track.

  A track may be of type `video`, `audio` or `application` (carrying metadata about a stream).
  It's used mainly to signal available streams between the different elements of a pipeline
  """

  @type media_type :: :application | :audio | :video
  @type media_codec :: atom()

  @type t :: %__MODULE__{
          type: media_type(),
          encoding: media_codec()
        }

  @enforce_keys [:type]
  defstruct @enforce_keys ++ [encoding: nil]

  @spec new(media_type(), media_codec()) :: t()
  def new(type, encoding) do
    encoding = if is_binary(encoding), do: String.to_existing_atom(encoding), else: encoding
    %__MODULE__{type: type, encoding: encoding}
  end
end
