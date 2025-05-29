defmodule ExNVR.Nerves.Monitoring.UPS do
  @moduledoc """
  Monitor AC and battery alarms.
  """

  use GenServer

  require Logger

  alias Circuits.GPIO
  alias ExNVR.Devices
  alias ExNVR.Nerves.{DiskMounter, SystemSettings}

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  def state(pid \\ __MODULE__) do
    GenServer.call(pid, :state)
  end

  @impl true
  def init(options) do
    ups_config = SystemSettings.get_settings().ups

    state =
      ups_config
      |> do_start_monitor(options)
      |> Map.put(:config, ups_config)

    SystemSettings.subscribe()

    if ups_config.enabled do
      {:ok, state, {:continue, :trigger_action}}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_continue(:trigger_action, state) do
    {ac_state, low_battery_state} =
      if state.config.enabled, do: {state.ac_ok?, state.low_battery?}, else: {1, 0}

    do_trigger_action(:ac_ok?, state.config.ac_failure_action, ac_state)
    do_trigger_action(:low_battery?, state.config.low_battery_action, low_battery_state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:state, _from, state) do
    reply =
      if state.config.enabled do
        %{ac_ok: to_bool(state.ac_ok?), low_battery: to_bool(state.low_battery?)}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_info({:system_settings, :update}, state) do
    ups_settings = SystemSettings.get_settings().ups

    :ok = clean_state(state)
    new_state = ups_settings |> do_start_monitor([]) |> Map.put(:config, ups_settings)

    {:noreply, new_state, {:continue, :trigger_action}}
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

    {:noreply, %{state | action_timer: ref}}
  end

  @impl true
  def handle_info({:trigger_action, :ac_ok?}, %{config: config} = state) do
    do_trigger_action(:ac_ok?, config.ac_failure_action, state.ac_ok?)
    {:noreply, %{state | action_timer: nil}}
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

  defp do_start_monitor(%{enabled: false}, _opts), do: %{}

  defp do_start_monitor(ups_config, opts) do
    ac_pin = Keyword.get(opts, :ac_pin, ups_config.ac_pin)
    bat_pin = Keyword.get(opts, :battery_pin, ups_config.battery_pin)

    {:ok, ac_gpio} = GPIO.open(ac_pin, :input, pull_mode: :pulldown)
    {:ok, bat_gpio} = GPIO.open(bat_pin, :input, pull_mode: :pulldown)

    :ok = GPIO.set_interrupts(bat_gpio, :both)
    :ok = GPIO.set_interrupts(ac_gpio, :both)

    %{
      ac_pin: ac_pin,
      bat_pin: bat_pin,
      ac_gpio: ac_gpio,
      bat_gpio: bat_gpio,
      ac_timer: nil,
      bat_timer: nil,
      action_timer: nil,
      ac_ok?: GPIO.read(ac_gpio),
      low_battery?: GPIO.read(bat_gpio)
    }
  end

  defp clean_state(state) do
    if state[:ac_gpio], do: GPIO.close(state.ac_gpio)
    if state[:bat_gpio], do: GPIO.close(state.bat_gpio)
    if state[:ac_timer], do: :timer.cancel(state.ac_timer)
    if state[:bat_timer], do: :timer.cancel(state.bat_timer)
    if state[:action_timer], do: Process.cancel_timer(state.action_timer)
    :ok
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
    stop_recording()
    Nerves.Runtime.poweroff()
  end

  defp stop_recording() do
    Logger.info("[UPS] stop recording")

    Devices.list()
    |> Enum.filter(&ExNVR.Model.Device.recording?/1)
    |> Enum.each(&ExNVR.Pipelines.Main.stop_recording/1)

    # avoid unmouting filesystem before the pipeline flush
    # the current recording.
    :timer.apply_after(to_timeout(second: 2), fn -> DiskMounter.umount() end)
  end

  defp start_recording() do
    Logger.info("[UPS] start recording")

    :ok = DiskMounter.mount()

    Devices.list()
    |> Enum.filter(&ExNVR.Model.Device.recording?/1)
    |> Enum.each(&ExNVR.Pipelines.Main.start_recording/1)
  end

  defp event_name(:ac_ok?), do: "power"
  defp event_name(:low_battery?), do: "low-battery"

  defp to_bool(0), do: false
  defp to_bool(_other), do: true
end
