defmodule ExNVR.AV.Hailo.API.NetworkGroup do
  @moduledoc """
  Represents a configured network group on a VDevice.
  """
  defstruct ref: nil,
            vdevice_ref: nil,
            # Placeholder, might need to get from NIF if available
            name: nil,
            input_vstream_infos: [],
            output_vstream_infos: []
end
