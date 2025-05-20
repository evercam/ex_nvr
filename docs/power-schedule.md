# Power Schedule

`ExNVR.Nerves.Monitoring.PowerSchedule` enforces the device's power policy based on a schedule stored in system settings.

## Overview

The GenServer monitors the schedule and triggers actions such as powering off the device or stopping pipelines when outside of the allowed window.

## Initialization

```elixir
@impl true
def init(_opts) do
  Logger.info("Starting power schedule monitoring")
  Process.send_after(self(), :check_schedule, to_timeout(minute: 5))
  {:ok, get_settings()}
end
```

The schedule and timezone are loaded from `ExNVR.Nerves.SystemSettings`.

## Periodic Checks

Every few minutes the server evaluates whether the device should stay on:

```elixir
def handle_info(:check_schedule, state) do
  ntp_synced? = NervesTime.synchronized?()

  cond do
    is_nil(state.schedule) ->
      Process.send_after(self(), :check_schedule, to_timeout(minute: 5))

    not ntp_synced? or Schedule.scheduled?(state.schedule, DateTime.now!(state.timezone)) ->
      if not ntp_synced? do
        Logger.warning("[Power schedule]: NTP not synched, skipping schedule check")
      end

      Process.send_after(self(), :check_schedule, to_timeout(second: 15))

    true ->
      trigger_action(state.action)
  end

  {:noreply, state}
end
```

## Actions

Depending on the configured `schedule_action` the following functions run:

```elixir
defp trigger_action("poweroff") do
  Logger.info("[Power schedule]: powering off the device")
  ExNVR.Events.create_event(%{type: "shutdown"})
  Enum.each(Devices.list(), &Devices.Supervisor.stop/1)
  Nerves.Runtime.poweroff()
end

defp trigger_action("stop_pipeline") do
  Logger.info("[Power schedule]: stopping all devices")
  Enum.each(Devices.list(), &Devices.Supervisor.stop/1)
end

defp trigger_action(action) do
  Logger.warning("[Power schedule]: unknown action #{inspect(action)}")
end
```

The settings are reloaded with `PowerSchedule.reload/0` whenever the remote configuration changes.
