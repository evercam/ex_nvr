defmodule ExNVR.Hardware.SerialPortChecker do
  @moduledoc """
  Module periodically checking new serial ports.

  The issue stems from this process starting before the OS detect all
  the serial ports (especially when running in nerves).
  """

  use GenServer

  @serial_ports_interval_check to_timeout(second: 30)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :check_serial_ports, 0)
    {:ok, nil}
  end

  @impl true
  def handle_info(:check_serial_ports, state) do
    start_victron_processes()
    Process.send_after(self(), :check_serial_ports, @serial_ports_interval_check)
    {:noreply, state}
  end

  defp start_victron_processes() do
    Circuits.UART.enumerate()
    |> Map.keys()
    |> Enum.filter(&(&1 not in ["ttyS0", "ttyS1", "ttyAMA0", "ttyAMA10"]))
    |> Enum.map(&[port: &1, name: :"victron_#{&1}"])
    |> Enum.filter(&is_nil(Process.whereis(&1.name)))
    |> Enum.each(&DynamicSupervisor.start_child(ExNVR.Hardware.Supervisor, {ExNVR.Hardware.Victron, &1}))
  end
end
