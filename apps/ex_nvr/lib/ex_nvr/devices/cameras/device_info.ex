defmodule ExNVR.Devices.Cameras.DeviceInfo do
  @moduledoc false

  @type t :: %__MODULE__{
          vendor: binary(),
          name: binary(),
          model: binary(),
          serial: binary(),
          firmware_version: binary()
        }

  defstruct [:vendor, :name, :model, :serial, :firmware_version]
end
