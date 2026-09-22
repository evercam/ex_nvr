defmodule ExNVR.Nerves.RecomputerR22.Init do
  @moduledoc false

  use GenServer

  require Logger

  alias Circuits.GPIO
  alias ExNVR.Nerves
  alias ExNVR.Nerves.RecomputerR22.{ATModem, SimConfigurer}

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

      with {:ok, _} <- ATModem.start() do
        if not sim_detected?(), do: ATModem.reboot()
        if sim_detected?(), do: setup_modem()
      end

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

  def sim_detected?, do: match?({:ok, _}, ATModem.sim_status())

  defp setup_modem do
    ensure_qmi_mode()

    case SimConfigurer.configure_apn() do
      {:ok, apn} -> configure_qmi_interface(apn)
      {:error, reason} -> Logger.error("[R22] failed to resolve APN: #{inspect(reason)}")
    end
  end

  def ensure_qmi_mode do
    case ATModem.usbnet_mode() do
      {:ok, :qmi} ->
        :ok

      {:ok, mode} ->
        Logger.info("[R22] modem using #{mode}, switching to QMI (wwan0)")
        switch_to_qmi()

      {:error, reason} ->
        {:error, {:usbnet_mode_unavailable, reason}}
    end
  end

  def switch_to_qmi do
    with {:ok, _} <- ATModem.set_usbnet_mode(:qmi),
         :ok <- ATModem.reboot() do
      :ok
    else
      {:error, reason} -> {:error, {:set_usbnet_failed, reason}}
    end
  end

  def configure_qmi_interface(apn) do
    VintageNet.configure("wwan0", %{
      type: VintageNetQMI,
      vintage_net_qmi: %{service_providers: [%{apn: apn}]}
    })
  end
end
