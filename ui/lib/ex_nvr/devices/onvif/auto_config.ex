defmodule ExNVR.Devices.Onvif.AutoConfig do
  @moduledoc false

  @type t :: %__MODULE__{
          main_stream: boolean(),
          sub_stream: boolean(),
          third_stream: boolean()
        }

  defstruct main_stream: false, sub_stream: false, third_stream: false
end
