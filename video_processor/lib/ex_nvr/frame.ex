defmodule ExNVR.AV.Frame do
  @moduledoc false

  @type format() :: atom()

  @type width :: non_neg_integer() | nil
  @type height :: non_neg_integer() | nil

  @type t() :: %__MODULE__{
          type: :video,
          data: binary(),
          format: format(),
          width: width(),
          height: height(),
          pts: integer()
        }

  defstruct [
    :type,
    :data,
    :format,
    :width,
    :height,
    :pts
  ]

  @spec new(binary(), keyword()) :: t()
  def new(data, opts) do
    struct(%__MODULE__{type: :video, data: data}, opts)
  end
end
