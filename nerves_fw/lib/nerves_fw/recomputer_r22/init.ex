defmodule ExNVR.Nerves.RecomputerR22.Init do
  @moduledoc false

  use GenServer

  require Logger

  alias Circuits.GPIO
  alias ExNVR.Nerves

  @max_attempts 20
  @retry_interval 1_000

  def start_link(_args) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, ups} = Nerves.GPIO.start_link(pin: "GPIO16", name: :ups, pull_mode: :pullup)

    state = %{
      attempts: 0,
      poe_pin: nil,
      m2b_power_off: nil,
      sim_mux_sel: nil,
      ups: ups
    }

    Process.send_after(self(), :init, 0)

    {:ok, state}
  end

  @impl true
  def handle_info(:init, %{attempts: attempts} = state) when attempts >= @max_attempts do
    Logger.error("GPIO chips not available after #{@max_attempts} attempts, giving up")
    {:noreply, state}
  end

  def handle_info(:init, state) do
    if gpiochips_available?() do
      state =
        state
        # PoE power control
        |> open_gpio(:poe_pin, {"gpiochip15", 13}, 1)
        # 4G modem
        |> open_gpio(:m2b_power_off, {"gpiochip16", 0}, 0)
        |> open_gpio(:sim_mux_sel, {"gpiochip16", 4}, 0)

      {:noreply, state}
    else
      Logger.warning(
        "gpiochip15 or gpiochip16 not yet available, retrying (attempt #{state.attempts + 1}/#{@max_attempts})"
      )

      Process.send_after(self(), :init, @retry_interval)
      {:noreply, %{state | attempts: state.attempts + 1}}
    end
  end

  def handle_info({pid, value}, %{ups: pid} = state) do
    Logger.info("[R22] UPS state changed: #{value}")
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if state.poe_pin, do: GPIO.close(state.poe_pin)
    if state.m2b_power_off, do: GPIO.close(state.m2b_power_off)
    if state.sim_mux_sel, do: GPIO.close(state.sim_mux_sel)
    :ok
  end

  defp gpiochips_available? do
    File.exists?("/dev/gpiochip15") and File.exists?("/dev/gpiochip16")
  end

  defp open_gpio(state, key, gpio, value) do
    case GPIO.open(gpio, :output) do
      {:ok, pin} ->
        GPIO.write(pin, value)
        Map.put(state, key, pin)

      {:error, reason} ->
        Logger.error("Failed to open GPIO #{inspect(gpio)}: #{inspect(reason)}")
        state
    end
  end
end
