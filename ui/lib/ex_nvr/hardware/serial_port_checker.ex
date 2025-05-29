defmodule ExNVR.Hardware.SerialPortChecker do
  @moduledoc """
  Module periodically checking new serial ports.

  The issue stems from this process starting before the OS detect all
  the serial ports (especially when running in nerves).
  """

  use GenServer

  require Logger

  @serial_ports_interval_check to_timeout(second: 30)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :check_serial_ports, 0)
    {:ok, %{serial_ports: ["ttyS0", "ttyS1", "ttyAMA0", "ttyAMA10"]}}
  end

  @impl true
  def handle_info(:check_serial_ports, state) do
    Logger.info("Checking for new serial ports")
    Process.send_after(self(), :check_serial_ports, @serial_ports_interval_check)

    serial_ports =
      Circuits.UART.enumerate()
      |> Map.keys()
      |> Kernel.--(state.serial_ports)

    serial_ports
    |> Enum.map(&[port: &1, name: :"victron_#{&1}"])
    |> Enum.filter(&is_nil(Process.whereis(&1[:name])))
    |> Enum.each(
      &DynamicSupervisor.start_child(ExNVR.Hardware.Supervisor, {ExNVR.Hardware.Victron, &1})
    )

    {:noreply, %{serial_ports: state.serial_ports ++ serial_ports}}
  end
end
