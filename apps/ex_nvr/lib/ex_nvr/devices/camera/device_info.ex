defmodule ExNVR.Devices.Camera.DeviceInfo do
  @moduledoc false

  @type t :: %__MODULE__{
          vendor: atom(),
          name: binary(),
          model: binary(),
          serial: binary(),
          mac: binary(),
          firmware_version: binary()
        }

  defstruct [:vendor, :name, :model, :serial, :mac, :firmware_version]
end
