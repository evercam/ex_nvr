defmodule ExNVR.Nerves.Monitoring.UPS do
  @moduledoc """
  Monitor AC and battery alarms.
  """

  use GenServer

  require Logger

  alias ExNVR.Devices
  alias ExNVR.Nerves.{DiskMounter, SystemSettings}
  alias ExNVR.Nerves.GPIO

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  def state(pid \\ __MODULE__) do
    GenServer.call(pid, :state)
  end

  @impl true
  def init(options) do
    state =
      SystemSettings.get_settings()
      |> Map.fetch!(:ups)
      |> do_start_monitor(options)
      |> maybe_enable_ups()

    SystemSettings.subscribe()

    if state.config.enabled do
      {:ok, state, {:continue, :trigger_action}}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_continue(:trigger_action, state) do
    {ac_state, low_battery_state} = if state.config.enabled, do: pin_state(state), else: {1, 0}

    do_trigger_action(:ac_ok?, state.config.ac_failure_action, ac_state)
    do_trigger_action(:low_battery?, state.config.low_battery_action, low_battery_state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:state, _from, %{config: %{enabled: true}} = state) do
    {ac_ok?, low_battery?} = pin_state(state)
    {:reply, %{ac_ok: ac_ok? == 1, low_battery: low_battery? == 1}, state}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, nil, state}
  end

  @impl true
  def handle_info({:system_settings, :update}, state) do
    ups_settings = SystemSettings.get_settings().ups

    :ok = clean_state(state)
    new_state = do_start_monitor(ups_settings, [])

    {:noreply, new_state, {:continue, :trigger_action}}
  end

  @impl true
  def handle_info({pid, _value}, %{config: %{enabled: false}} = state) when is_pid(pid) do
    # After updating the ups settings, this module will receive a notification and
    # will trigger the actions
    {:ok, %{ups: ups}} = SystemSettings.update_ups_settings(%{enabled: true})
    {:noreply, %{state | config: ups}}
  end

  @impl true
  def handle_info({ac_pid, value}, %{ac_pid: ac_pid} = state) do
    do_handle_pin_state_change(:ac_ok?, value, state)
  end

  @impl true
  def handle_info({bat_pid, value}, %{bat_pid: bat_pid} = state) do
    do_handle_pin_state_change(:low_battery?, value, state)
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

  defp do_start_monitor(ups_config, opts) do
    ac_pin = Keyword.get(opts, :ac_pin, ups_config.ac_pin)
    bat_pin = Keyword.get(opts, :battery_pin, ups_config.battery_pin)

    {:ok, ac_pid} = GPIO.start_link(pin: ac_pin)
    {:ok, bat_pid} = GPIO.start_link(pin: bat_pin)

    %{
      config: ups_config,
      ac_pin: ac_pin,
      bat_pin: bat_pin,
      ac_pid: ac_pid,
      bat_pid: bat_pid,
      action_timer: nil
    }
  end

  defp do_handle_pin_state_change(key, value, state) do
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

  defp maybe_enable_ups(state) do
    cond do
      state.config.enabled ->
        state

      GPIO.value(state.ac_pid) == 1 or GPIO.value(state.bat_pid) == 1 ->
        Logger.info("[UPS] auto enable UPS monitoring")
        {:ok, %{ups: ups}} = SystemSettings.update_ups_settings(%{enabled: true})
        %{state | config: ups}

      true ->
        state
    end
  end

  defp clean_state(state) do
    if state[:action_timer], do: Process.cancel_timer(state.action_timer)
    :ok = GenServer.stop(state.ac_pid)
    :ok = GenServer.stop(state.bat_pid)
    :ok
  end

  defp do_trigger_action(:ac_ok?, :power_off, 0), do: power_off()
  defp do_trigger_action(:low_battery?, :power_off, 1), do: power_off()
  defp do_trigger_action(:ac_ok?, :stop_recording, 0), do: stop_recording()
  defp do_trigger_action(:low_battery?, :stop_recording, 1), do: stop_recording()
  defp do_trigger_action(:ac_ok?, :stop_recording, 1), do: start_recording()
  defp do_trigger_action(:low_battery?, :stop_recording, 0), do: start_recording()
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

  defp pin_state(state) do
    {GPIO.value(state.ac_pid), GPIO.value(state.bat_pid)}
  end
end
