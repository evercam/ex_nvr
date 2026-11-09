defmodule ExNVR.Devices.Cameras.RecordingSettings do
  @moduledoc false

  @type t :: %__MODULE__{
          stream: :main | :sub | :third,
          schedule: :always,
          overwrite: boolean()
        }

  # recording on the camera storage (e.g. SD card)
  defstruct stream: :main, schedule: :always, overwrite: true
end
