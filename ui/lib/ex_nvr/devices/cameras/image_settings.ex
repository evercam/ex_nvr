defmodule ExNVR.Devices.Cameras.ImageSettings do
  @moduledoc false

  @type t :: %__MODULE__{
          brightness: 0..100 | nil,
          contrast: 0..100 | nil,
          saturation: 0..100 | nil
        }

  # nil fields are left unchanged on the camera
  defstruct [:brightness, :contrast, :saturation]
end
