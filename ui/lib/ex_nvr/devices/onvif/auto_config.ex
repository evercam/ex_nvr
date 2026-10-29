defmodule ExNVR.Devices.Onvif.AutoConfig do
  @moduledoc false

  @type t :: %__MODULE__{
          main_stream: boolean(),
          sub_stream: boolean(),
          third_stream: boolean(),
          image_settings: boolean(),
          osd: boolean()
        }

  defstruct main_stream: false,
            sub_stream: false,
            third_stream: false,
            image_settings: false,
            osd: false
end
