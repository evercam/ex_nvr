defmodule ExNVR.SystemStatus.State do
  @moduledoc """
  A struct describing the state of the system.
  """

  alias ExNVR.Hardware.SolarCharger.VictronMPPT

  @type t :: %__MODULE__{
          version: binary(),
          memory: [{atom(), integer()}],
          cpu: %{load: [float()], num_cores: integer()},
          block_storage: [ExNVR.Disk.t()],
          solar_charger: VictronMPPT.t() | nil,
          router: map() | nil
        }

  @derive Jason.Encoder
  defstruct [:version, :memory, :cpu, :block_storage, :solar_charger, :router]
end
