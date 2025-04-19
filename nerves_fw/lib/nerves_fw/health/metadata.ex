defmodule ExNVR.Nerves.Health.Metadata do
  @moduledoc false

  alias ExNVR.Nerves.Hardware.RUT

  @spec router_serial_number() :: String.t() | nil
  def router_serial_number(), do: router_state()[:serial_number]

  @spec router_mac_address() :: String.t() | nil
  def router_mac_address(), do: router_state()[:mac_address]

  defp router_state() do
    if Process.whereis(RUT), do: RUT.state(), else: %{}
  end
end
