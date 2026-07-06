defmodule ExNVR.Hardware.SerialPortChecker do
  @moduledoc """
  Module periodically checking new serial ports.

  The issue stems from this process starting before the OS detect all
  the serial ports (especially when running in nerves).
  """

  use GenServer

  require Logger

  @serial_ports_interval_check to_timeout(minute: 1)
  @ignore_ports ["ttyS0", "ttyS1", "ttyAMA0", "ttyAMA10"]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enable Victron serial port probing.
  """
  @spec enable() :: :ok
  def enable, do: GenServer.call(__MODULE__, :enable)

  @doc """
  Disable Victron serial port probing.
  """
  @spec disable() :: :ok
  def disable, do: GenServer.call(__MODULE__, :disable)

  @doc "Whether probing is currently enabled."
  @spec enabled?() :: boolean()
  def enabled?, do: GenServer.call(__MODULE__, :enabled?)

  @impl true
  def init(_opts) do
    enabled? = Application.get_env(:ex_nvr, :victron_probing, false)
    {:ok, schedule_check(%{enabled?: enabled?, timer: nil, started: MapSet.new()}, 0)}
  end

  @impl true
  def handle_call(:enable, _from, %{enabled?: true} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:enable, _from, state) do
    Logger.info("Enabling serial port probing")
    {:reply, :ok, schedule_check(%{state | enabled?: true}, 0)}
  end

  def handle_call(:disable, _from, state) do
    Logger.info("Disabling serial port probing")

    state =
      %{state | enabled?: false}
      |> cancel_timer()
      |> stop_started()

    {:reply, :ok, state}
  end

  def handle_call(:enabled?, _from, state) do
    {:reply, state.enabled?, state}
  end

  @impl true
  def handle_info(:check_serial_ports, %{enabled?: false} = state) do
    {:noreply, %{state | timer: nil}}
  end

  def handle_info(:check_serial_ports, state) do
    Logger.info("Checking for new serial ports")

    started =
      Circuits.UART.enumerate()
      |> Map.keys()
      |> Kernel.--(@ignore_ports)
      |> Enum.map(&[port: &1, name: :"victron_#{&1}"])
      |> Enum.filter(&is_nil(Process.whereis(&1[:name])))
      |> Enum.reduce(state.started, fn args, acc ->
        case DynamicSupervisor.start_child(
               ExNVR.Hardware.Supervisor,
               {ExNVR.Hardware.Victron, args}
             ) do
          {:ok, _pid} -> MapSet.put(acc, args[:name])
          _error -> acc
        end
      end)

    {:noreply, schedule_check(%{state | started: started}, @serial_ports_interval_check)}
  end

  defp schedule_check(%{enabled?: false} = state, _delay), do: state

  defp schedule_check(state, delay) do
    state = cancel_timer(state)
    %{state | timer: Process.send_after(self(), :check_serial_ports, delay)}
  end

  defp cancel_timer(%{timer: nil} = state), do: state

  defp cancel_timer(%{timer: timer} = state) do
    Process.cancel_timer(timer)
    %{state | timer: nil}
  end

  defp stop_started(state) do
    Enum.each(state.started, fn name ->
      if pid = Process.whereis(name) do
        DynamicSupervisor.terminate_child(ExNVR.Hardware.Supervisor, pid)
      end
    end)

    %{state | started: MapSet.new()}
  end
end
