defmodule ExNVR.Nerves.Giraffe.Init do
  @moduledoc """
  Init Giraffe board.

  The following actions will be run at startup:
    * Power on HDD (GPIO16)
    * Power on PoE (GPIO26)
    * Monitor status of GPIO10 (Generator)
  """

  use GenServer, restart: :transient

  require Logger

  alias ExNVR.Nerves.GPIO
  alias ExNVR.Nerves.{SystemSettings, SystemStatus}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil)
  end

  @impl true
  def init(_options) do
    res =
      SystemSettings.update(%{
        ups: %{
          enabled: true,
          ac_pin: "GPIO4",
          battery_pin: "GPIO8",
          ac_pin_default: 1,
          battery_pin_default: 1,
          trigger_after: 0,
          low_battery_action: :power_off,
          ac_failure_action: :nothing
        }
      })

    with {:error, _} <- res do
      Logger.error("[Init] failed to update ups settings")
    end

    {:ok, nil, {:continue, :init}}
  end

  @impl true
  def handle_continue(:init, _state) do
    :ok = Circuits.GPIO.write_one("GPIO16", 1)
    :ok = Circuits.GPIO.write_one("GPIO26", 1)

    {:ok, generator_pid} = GPIO.start_link(pin: "GPIO10")
    state = %{generator: %{pid: generator_pid, state: generator_state(GPIO.value(generator_pid))}}

    {:noreply, state}
  end

  @impl true
  def handle_info({gen_pid, value}, %{generator: %{pid: gen_pid}} = state) do
    status =
      case value do
        0 -> :on
        1 -> :off
      end

    :ok = SystemStatus.set(:generator, status)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp generator_state(0), do: :on
  defp generator_state(_), do: :off
end
