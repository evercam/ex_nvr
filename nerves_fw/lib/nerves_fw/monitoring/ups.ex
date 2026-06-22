defmodule ExNVR.Nerves.Monitoring.UPS do
  @moduledoc """
  Monitor AC and battery alarms.
  """

  use GenServer

  require Logger

  alias ExNVR.{Devices, Model, Pipelines}
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
      |> arm_open_retry()

    SystemSettings.subscribe()

    if state.config.enabled do
      {:ok, state, {:continue, :trigger_action}}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_continue(:trigger_action, state) do
    do_trigger_action(state.config.ac_failure_action, pin_state(state, :ac_ok?))
    do_trigger_action(state.config.low_battery_action, pin_state(state, :low_battery?))
    {:noreply, state}
  end

  @impl true
  def handle_call(:state, _from, %{config: %{enabled: true}} = state) do
    {:reply,
     %{
       ac_ok: pin_state(state, :ac_ok?) == :up,
       low_battery: pin_state(state, :low_battery?) == :down
     }, state}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, nil, state}
  end

  @impl true
  def handle_info({:system_settings, :update}, state) do
    ups_settings = SystemSettings.get_settings().ups

    :ok = clean_state(state)
    new_state = ups_settings |> do_start_monitor([]) |> arm_open_retry()

    {:noreply, new_state, {:continue, :trigger_action}}
  end

  @impl true
  def handle_info(:retry_open, state) do
    new_state = state.config |> do_start_monitor(log_errors: false) |> arm_open_retry()
    reopened? = monitoring?(new_state)

    if reopened?, do: Logger.info("[UPS] GPIO pins re-opened, monitoring re-established")

    if reopened? and new_state.config.enabled do
      {:noreply, new_state, {:continue, :trigger_action}}
    else
      {:noreply, new_state}
    end
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
    do_trigger_action(config.ac_failure_action, pin_state(state, :ac_ok?))
    {:noreply, put_action_timer(state, :ac_ok?, nil)}
  end

  @impl true
  def handle_info({:trigger_action, :low_battery?}, %{config: config} = state) do
    do_trigger_action(config.low_battery_action, pin_state(state, :low_battery?))
    {:noreply, put_action_timer(state, :low_battery?, nil)}
  end

  @impl true
  def handle_info(message, state) do
    Logger.warning("Received unexpected message: #{inspect(message)}")
    {:noreply, state}
  end

  defp do_start_monitor(ups_config, opts) do
    ac_pin = Keyword.get(opts, :ac_pin, ups_config.ac_pin)
    bat_pin = Keyword.get(opts, :battery_pin, ups_config.battery_pin)

    base = %{
      config: ups_config,
      ac_pin: ac_pin,
      bat_pin: bat_pin,
      ac_pid: nil,
      bat_pid: nil,
      action_timers: %{},
      retry_timer: nil
    }

    case open_pins(ac_pin, bat_pin) do
      {:ok, ac_pid, bat_pid} ->
        %{base | ac_pid: ac_pid, bat_pid: bat_pid}

      {:error, reason} ->
        # A GPIO open can fail on hardware quirks (chip/pin unavailable, already
        # in use). Degrade to disabled monitoring instead of letting the
        # MatchError crash init and crash-loop the whole firmware supervisor;
        # arm_open_retry/1 then schedules a calm re-open so a transient fault
        # recovers on its own. Stay quiet on the repeated retries (log_errors).
        if Keyword.get(opts, :log_errors, true) do
          Logger.error(
            "[UPS] could not open GPIO pins (ac: #{inspect(ac_pin)}, battery: " <>
              "#{inspect(bat_pin)}), monitoring disabled, retrying every " <>
              "#{div(open_retry_interval(), 1000)}s: #{inspect(reason)}"
          )
        end

        base
    end
  end

  # Re-open the pins on a calm fixed interval while monitoring is degraded, so a
  # transient GPIO fault heals without a settings change or reboot. No-op once
  # the pins are open.
  defp arm_open_retry(%{ac_pid: pid} = state) when not is_nil(pid), do: state

  defp arm_open_retry(state) do
    %{state | retry_timer: Process.send_after(self(), :retry_open, open_retry_interval())}
  end

  defp monitoring?(state), do: not is_nil(state.ac_pid)

  defp open_retry_interval do
    Application.get_env(:ex_nvr_fw, :ups_open_retry_interval, to_timeout(second: 60))
  end

  # Open both GPIO pins, stopping the first if the second fails so we don't leak
  # a live GPIO process when degrading to disabled monitoring.
  defp open_pins(ac_pin, bat_pin) do
    case start_gpio(ac_pin) do
      {:ok, ac_pid} ->
        case start_gpio(bat_pin) do
          {:ok, bat_pid} ->
            {:ok, ac_pid, bat_pid}

          {:error, _reason} = error ->
            stop_gpio(ac_pid)
            error
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp start_gpio(pin) do
    case GPIO.start_link(pin: pin) do
      {:ok, pid} -> {:ok, pid}
      {:error, _reason} = error -> error
    end
  end

  defp stop_gpio(nil), do: :ok

  defp stop_gpio(pid) do
    GenServer.stop(pid)
  catch
    # already dead / never started — nothing to clean up
    :exit, _reason -> :ok
  end

  defp do_handle_pin_state_change(key, value, state) do
    Logger.warning("[UPS] #{key} changed to #{value}")
    event = %{type: event_name(key), metadata: %{state: value}}

    Logger.info("[UPS] store event for #{key}")

    with {:error, changeset} <- ExNVR.Events.create_event(event) do
      Logger.error("Failed to save event: #{inspect(changeset)}")
    end

    # Cancel only this alarm's own pending action — AC and battery keep separate
    # timers, so a change on one alarm never drops a shutdown already scheduled
    # for the other (e.g. a battery blip must not cancel a pending AC poweroff).
    cancel_action_timer(state, key)

    ref =
      if action_configured?(state.config, key) do
        Process.send_after(
          self(),
          {:trigger_action, key},
          to_timeout(second: state.config.trigger_after)
        )
      end

    {:noreply, put_action_timer(state, key, ref)}
  end

  defp action_configured?(config, :ac_ok?), do: config.ac_failure_action != :nothing
  defp action_configured?(config, :low_battery?), do: config.low_battery_action != :nothing

  defp cancel_action_timer(state, key) do
    case Map.get(state.action_timers, key) do
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end
  end

  defp put_action_timer(state, key, ref) do
    %{state | action_timers: Map.put(state.action_timers, key, ref)}
  end

  defp maybe_enable_ups(%{ac_pid: nil} = state), do: state

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
    state
    |> Map.get(:action_timers, %{})
    |> Map.values()
    |> Enum.each(fn ref -> if ref, do: Process.cancel_timer(ref) end)

    if state[:retry_timer], do: Process.cancel_timer(state.retry_timer)

    stop_gpio(state.ac_pid)
    stop_gpio(state.bat_pid)
    :ok
  end

  defp do_trigger_action(:power_off, :down), do: power_off()
  defp do_trigger_action(:stop_recording, :down), do: stop_recording()
  defp do_trigger_action(:stop_recording, :up), do: start_recording()
  defp do_trigger_action(_action, _value), do: :ok

  defp power_off do
    Logger.info("[UPS] shutdown system")
    stop_recording()
    Nerves.Runtime.poweroff()
  end

  defp stop_recording do
    Logger.info("[UPS] stop recording")

    Devices.list()
    |> Enum.filter(&Model.Device.recording?/1)
    |> Enum.each(&Pipelines.Main.stop_recording/1)

    # avoid unmouting filesystem before the pipeline flush
    # the current recording.
    :timer.apply_after(to_timeout(second: 2), fn -> DiskMounter.umount() end)
  end

  defp start_recording do
    Logger.info("[UPS] start recording")

    :ok = DiskMounter.mount()

    Devices.list()
    |> Enum.filter(&Model.Device.recording?/1)
    |> Enum.each(&Pipelines.Main.start_recording/1)
  end

  defp event_name(:ac_ok?), do: "power"
  defp event_name(:low_battery?), do: "low-battery"

  # :down means the gpio triggered / :up normal state
  defp pin_state(state, :ac_ok?), do: pin_value(state.ac_pid, state.config.ac_pin_default)

  defp pin_state(state, :low_battery?),
    do: pin_value(state.bat_pid, state.config.battery_pin_default)

  # With monitoring disabled (no GPIO opened) default to :up (normal) so a
  # degraded UPS never triggers a spurious power-off / stop-recording.
  defp pin_value(nil, _default), do: :up

  defp pin_value(pid, default) do
    if GPIO.value(pid) != default, do: :down, else: :up
  end
end
