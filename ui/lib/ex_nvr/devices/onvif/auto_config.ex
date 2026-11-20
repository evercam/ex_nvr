defmodule ExNVR.Devices.Onvif.AutoConfig do
  @moduledoc false

  alias ExNVR.Devices.Cameras.Firmware

  # nil means the step was not run
  @type result :: :ok | {:error, term()} | nil

  @type t :: %__MODULE__{
          date_time: result(),
          main_stream: result(),
          sub_stream: result(),
          third_stream: result(),
          image_settings: result(),
          osd: result(),
          sd_card: result(),
          sd_recording: result(),
          # the upgrade itself runs in background, see `ExNVR.Devices.Onvif.upgrade_firmware/3`
          firmware: result() | {:upgrade, current_version :: String.t(), Firmware.t()}
        }

  defstruct [
    :date_time,
    :main_stream,
    :sub_stream,
    :third_stream,
    :image_settings,
    :osd,
    :sd_card,
    :sd_recording,
    :firmware
  ]
end
