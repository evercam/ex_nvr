defmodule ExNVR.SystemStatus.State do
  @moduledoc """
  A struct describing the state of the system.
  """

  alias ExNVR.Hardware.SolarCharger.VictronMPPT

  @type t :: %__MODULE__{
          memory: [{atom(), integer()}],
          cpu_load: tuple(),
          solar_charger: VictronMPPT.t() | nil
        }

  defstruct [:memory, :cpu_load, :solar_charger]
end
