defmodule ExNVR.SystemStatus.State do
  @moduledoc """
  A struct describing the state of the system.
  """

  alias ExNVR.Hardware.SolarCharger.VictronMPPT

  @type t :: %__MODULE__{
          memory: [{atom(), integer()}],
          cpu: %{load_avg: {float(), float(), float()}, num_cores: integer()},
          solar_charger: VictronMPPT.t() | nil
        }

  @derive Jason.Encoder
  defstruct [:memory, :cpu, :solar_charger]
end
