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

  alias ExNVR.Hardware.SerialPortChecker
  alias ExNVR.Nerves.GPIO
  alias ExNVR.Nerves.{SystemSettings, SystemStatus}

  @ups_config %{
    enabled: true,
    ac_pin: "GPIO4",
    battery_pin: "GPIO8",
    ac_pin_default: 1,
    battery_pin_default: 1,
    trigger_after: 0,
    low_battery_action: :power_off,
    ac_failure_action: :nothing
  }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil)
  end

  @doc """
  Enable UPS monitoring when the power type is `:mains`, disable it otherwise.
  """
  @spec set_ups(atom()) :: :ok | :error
  def set_ups(:mains), do: update_ups(@ups_config)
  def set_ups(_power_type), do: update_ups(%{enabled: false})

  @impl true
  def init(_options) do
    power_type = SystemSettings.get_settings() |> Map.fetch!(:power_type)

    set_ups(power_type)
    enable_victron_monitoring(power_type)

    {:ok, nil, {:continue, :init}}
  end

  @impl true
  def handle_continue(:init, _state) do
    :ok = Circuits.GPIO.write_one("GPIO16", 1)
    :ok = Circuits.GPIO.write_one("GPIO26", 1)

    {:ok, generator_pid} = GPIO.start_link(pin: "GPIO10")
    state = %{generator: generator_pid}
    :ok = SystemStatus.set(:generator, generator_state(GPIO.value(generator_pid)))

    {:noreply, state}
  end

  @impl true
  def handle_info({gen_pid, value}, %{generator: gen_pid} = state) do
    :ok = SystemStatus.set(:generator, generator_state(value))
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp enable_victron_monitoring(power_type) when power_type in [:solar, :generator] do
    SerialPortChecker.enable()
  end

  defp enable_victron_monitoring(_power_type), do: SerialPortChecker.disable()

  defp generator_state(0), do: :on
  defp generator_state(_), do: :off

  defp update_ups(params) do
    case SystemSettings.update(%{ups: params}) do
      {:ok, _settings} ->
        :ok

      {:error, _reason} ->
        Logger.error("[Init] failed to update ups settings")
        :error
    end
  end
end
