defmodule ExNVR.SystemStatus.Supervisor do
  @moduledoc """
  Module responsible for starting and supervising system status processes.
  """

  use Supervisor

  alias ExNVR.Hardware.SolarCharger.VictronMPPT
  alias ExNVR.SystemStatus.{Registry, State}

  def start_link(options) do
    Supervisor.start_link(__MODULE__, options, name: __MODULE__)
  end

  @spec get_system_status() :: State.t()
  def get_system_status(), do: Registry.get_state()

  def init(_options) do
    registry_name = Registry

    children =
      [
        {Registry, [name: registry_name]}
      ] ++ maybe_start_victron_mppt(registry_name)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp maybe_start_victron_mppt(registry_name) do
    # VE.DIRECT to usb
    Circuits.UART.enumerate()
    |> Enum.find(fn {_port, details} ->
      details[:manufacturer] == "VictronEnergy BV" and details[:vendor_id] == 1027
    end)
    |> case do
      {port, _details} -> [{VictronMPPT, [port: port, registry: registry_name]}]
      nil -> []
    end
  end
end
