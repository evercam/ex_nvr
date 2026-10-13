defmodule ExNVR.Devices.Cameras.RemoteRecording do
  @moduledoc false

  @type t :: %__MODULE__{
          id: binary(),
          start_date: DateTime.t(),
          end_date: DateTime.t(),
          size: non_neg_integer(),
          type: :schedule | :alarm | :unknown,
          priv_data: map()
        }

  # priv_data holds vendor specific data needed to download the recording
  defstruct [:id, :start_date, :end_date, :size, :type, priv_data: %{}]
end
