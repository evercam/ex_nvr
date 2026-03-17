defmodule ExNVR.AV.Hailo.API.VStreamInfo do
  @moduledoc false

  defstruct name: nil,
            network_name: nil,
            direction: nil,
            frame_size: 0,
            format: %{},
            shape: nil,
            nms_shape: nil,
            quant_info: nil

  @type t :: %__MODULE__{
          name: String.t() | nil,
          network_name: String.t() | nil,
          direction: :h2d | :d2h | nil,
          frame_size: non_neg_integer(),
          format: map(),
          shape: map() | nil,
          nms_shape: map() | nil,
          quant_info: map() | nil
        }

  @struct_keys ~w(name network_name direction frame_size format shape nms_shape quant_info)a

  def from_map(map) when is_map(map) do
    fields =
      for key <- @struct_keys, into: %{} do
        {key, map[key] || map[Atom.to_string(key)]}
      end

    struct(__MODULE__, fields)
  end
end
