defmodule ExNVR.Pipeline.Track do
  @moduledoc """
  A module describing a track.

  A track may be of type `video`, `audio` or `application` (carrying metadata about a stream).
  It's used mainly to signal available streams between the different elements of a pipeline
  """

  alias __MODULE__.Stat

  @type media_type :: :application | :audio | :video
  @type media_codec :: atom()

  @type t :: %__MODULE__{
          type: media_type(),
          encoding: media_codec(),
          timescale: non_neg_integer(),
          stats: Stat.t() | nil
        }

  @derive Jason.Encoder
  @enforce_keys [:type]
  defstruct @enforce_keys ++ [encoding: nil, stats: nil, timescale: 0]

  @spec new(media_type(), media_codec(), Keyword.t()) :: t()
  def new(type, encoding, opts \\ []) do
    encoding = encoding |> to_string() |> String.downcase() |> String.to_atom()
    %__MODULE__{type: type, encoding: encoding} |> struct!(opts)
  end

  @spec new(ExMP4.Track.t()) :: t()
  def new(%ExMP4.Track{} = track) do
    %__MODULE__{type: track.type, encoding: track.media, timescale: track.timescale}
  end
end
