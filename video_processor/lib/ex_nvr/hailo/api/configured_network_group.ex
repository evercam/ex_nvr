defmodule ExNVR.AV.Hailo.API.NetworkGroup do
  @moduledoc false

  defstruct ref: nil,
            vdevice_ref: nil,
            name: nil,
            input_vstream_infos: [],
            output_vstream_infos: []

  @type t :: %__MODULE__{
          ref: reference() | nil,
          vdevice_ref: reference() | nil,
          name: String.t() | nil,
          input_vstream_infos: [ExNVR.AV.Hailo.API.VStreamInfo.t()],
          output_vstream_infos: [ExNVR.AV.Hailo.API.VStreamInfo.t()]
        }
end
