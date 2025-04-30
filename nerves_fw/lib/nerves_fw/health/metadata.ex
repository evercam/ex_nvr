defmodule ExNVR.Nerves.Health.Metadata do
  @moduledoc false

  alias ExNVR.Nerves.RUT

  @spec router_serial_number() :: String.t() | nil
  def router_serial_number(), do: Map.get(router_state(), :serial)

  @spec router_mac_address() :: String.t() | nil
  def router_mac_address(), do: Map.get(router_state(), :mac)

  defp router_state() do
    case RUT.system_information() do
      {:ok, info} -> info
      {:error, reason} -> %{}
    end
  end
end
