defmodule ExNVR.Devices.Cameras.DateTimeSettings do
  @moduledoc false

  @type t :: %__MODULE__{
          timezone: String.t(),
          ntp_server: String.t()
        }

  # timezone is an IANA timezone, e.g. "Europe/Dublin"
  defstruct [:timezone, :ntp_server]
end
