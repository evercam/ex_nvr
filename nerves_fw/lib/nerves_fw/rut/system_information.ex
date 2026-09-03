defmodule ExNVR.Nerves.RUT.SystemInformation do
  @moduledoc false

  @derive Jason.Encoder
  defstruct [:name, :serial, :mac, :model, :fw_version]
end
