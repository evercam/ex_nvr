defmodule ExNVR.Nerves.Monitoring.UPS do
  @moduledoc """
  Monitor AC and battery alarms.

  We'll use the following GPIO pins to monitor the power supply:
    * GPIO16 (input) - `1` low battery level
    * GPIO23 (input) - `0` AC failure.
  """

  use GenServer

  require Logger

  alias Circuits.GPIO
  alias ExNVR.Devices
  alias ExNVR.Nerves.SystemSettings

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  # force_read? read state even if publish? is false
  def state(force_read? \\ false, pid \\ __MODULE__) do
    GenServer.call(pid, {:state, force_read?})
  end

  @impl true
  def init(options) do
    ups_config = SystemSettings.get_settings().ups

    ac_pin = Keyword.get(options, :ac_pin, ups_config.ac_pin)
    bat_pin = Keyword.get(options, :battery_pin, ups_config.battery_pin)

    {:ok, ac_gpio} = GPIO.open(ac_pin, :input, pull_mode: :pulldown)
    {:ok, bat_gpio} = GPIO.open(bat_pin, :input, pull_mode: :pulldown)

    :ok = GPIO.set_interrupts(bat_gpio, :both)
    :ok = GPIO.set_interrupts(ac_gpio, :both)

    # publish? is set to true if system is wired for monitoring power.
    state = %{
      ac_pin: ac_pin,
      bat_pin: bat_pin,
      ac_gpio: ac_gpio,
      bat_gpio: bat_gpio,
      ac_timer: nil,
      bat_timer: nil,
      action_timer: nil,
      ac_ok?: GPIO.read(ac_gpio),
      low_battery?: GPIO.read(bat_gpio),
      config: ups_config
    }

    SystemSettings.subscribe()

    {:ok, state}
  end

  @impl true
  def handle_call({:state, force_read?}, _from, state) do
    reply =
      if state.config.enabled or force_read? do
        %{ac_ok?: to_bool(state.ac_ok?), low_battery?: to_bool(state.low_battery?)}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_info({:system_settings, :update}, state) do
    {:noreply, %{state | config: SystemSettings.get_settings().ups}}
  end

  @impl true
  def handle_info({:circuits_gpio, pin, _timestamp, value}, state) do
    {timer_field, field} =
      case state do
        %{ac_pin: ^pin} -> {:ac_timer, :ac_ok?}
        %{bat_pin: ^pin} -> {:bat_timer, :low_battery?}
      end

    # Timer used for debounce
    # We need to wait for the signal to stabilize before we can read it.
    :timer.cancel(state[timer_field])
    {:ok, ref} = :timer.send_after(to_timeout(second: 1), {:update, field, value})
    {:noreply, Map.put(state, timer_field, ref)}
  end

  @impl true
  def handle_info({:update, :ac_ok?, value}, %{ac_ok?: value} = state), do: {:noreply, state}

  @impl true
  def handle_info({:update, :low_battery?, value}, %{low_battery?: value} = state),
    do: {:noreply, state}

  @impl true
  def handle_info({:update, key, value}, state) do
    Logger.info("[UPS] #{key} changed to #{value}")
    state = Map.put(state, key, value)
    event = %{type: event_name(key), metadata: %{state: value}}

    with {:error, changeset} <- ExNVR.Events.create_event(event) do
      Logger.error("Failed to save event: #{inspect(changeset)}")
    end

    ref =
      if (key == :ac_ok? and state.config.ac_failure_action != :nothing) or
           (key == :low_battery? and state.config.low_battery_action != :nothing) do
        Process.send_after(
          self(),
          {:trigger_action, key},
          to_timeout(second: state.config.trigger_after)
        )
      end

    if state.action_timer, do: Process.cancel_timer(state.action_timer)

    settings = SystemSettings.update_ups_settings(%{enabled: true})
    {:noreply, %{state | config: settings.ups, action_timer: ref}}
  end

  @impl true
  def handle_info({:trigger_action, :ac_ok?}, %{config: config} = state) do
    do_trigger_action(:ac_ok?, config.ac_failure_action, state.ac_ok?)
    {:noreply,%{state | action_timer: nil}}
  end

  @impl true
  def handle_info({:trigger_action, :low_battery?}, %{config: config} = state) do
    do_trigger_action(:low_battery?, config.low_battery_action, state.low_battery?)
    {:noreply, %{state | action_timer: nil}}
  end

  @impl true
  def handle_info(message, state) do
    Logger.warning("Received unexpected message: #{inspect(message)}")
    {:noreply, state}
  end

  defp do_trigger_action(:ac_ok?, :power_off, 0), do: power_off()
  defp do_trigger_action(:low_battery?, :power_off, 1), do: power_off()
  defp do_trigger_action(:ac_ok?, :stop_recording, 0), do: stop_recording()
  defp do_trigger_action(:low_battery?, :stop_recording, 1), do: stop_recording()
  defp do_trigger_action(:ac_ok?, :stop_recording, 1), do: start_recording()
  defp do_trigger_action(:low_battery?, :stop_recording, 0), do: start_recording()
  # should not happen
  defp do_trigger_action(_key, _action, _value), do: :ok

  defp power_off() do
    Logger.info("[UPS] shutodwn system")
    Nerves.Runtime.poweroff()
  end

  defp stop_recording() do
    Logger.info("[UPS] stop recording")
    Enum.each(Devices.list(), &Devices.Supervisor.stop/1)
  end

  defp start_recording() do
    Logger.info("[UPS] start recording")
    Devices.start_all()
  end

  defp event_name(:ac_ok?), do: "power"
  defp event_name(:low_battery?), do: "low-battery"

  defp to_bool(0), do: false
  defp to_bool(_other), do: true
end
