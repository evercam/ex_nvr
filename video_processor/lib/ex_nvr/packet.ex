defmodule ExNVR.AV.Packet do
  @moduledoc """
  A module representing an audio/video compressed data.
  """

  @type t :: %__MODULE__{
          data: binary(),
          dts: integer(),
          pts: integer(),
          keyframe?: boolean()
        }

  defstruct [:data, :dts, :pts, :keyframe?]

  @spec new(Enumerable.t()) :: t()
  def new(opts) do
    struct!(%__MODULE__{}, opts)
  end
end
