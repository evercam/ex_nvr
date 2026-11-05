defmodule ExNVR.Devices.Onvif.AutoConfig do
  @moduledoc false

  # nil means the step was not run
  @type result :: :ok | {:error, term()} | nil

  @type t :: %__MODULE__{
          main_stream: result(),
          sub_stream: result(),
          third_stream: result(),
          image_settings: result(),
          osd: result()
        }

  defstruct [:main_stream, :sub_stream, :third_stream, :image_settings, :osd]
end
