# Hardware Power Monitoring

`ExNVR.Nerves.Hardware.Power` watches GPIO pins for AC failure and low battery alarms.

## Pins

- **GPIO16** – input pin that goes high when the battery level is low.
- **GPIO23** – input pin that goes low when AC power is lost.

## Initialization

```elixir
def init(options) do
  system_settings = SystemSettings.get_settings()

  ac_pin = Keyword.get(options, :ac_pin, "GPIO23")
  bat_pin = Keyword.get(options, :battery_pin, "GPIO16")

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
    ac_ok?: GPIO.read(ac_gpio),
    low_battery?: GPIO.read(bat_gpio),
    publish?: system_settings.monitor_power == true
  }

  {:ok, state}
end
```

## Handling GPIO Interrupts

Every change on the monitored pins schedules an update after one second to debounce the event:

```elixir
def handle_info({:circuits_gpio, pin, _timestamp, value}, state) do
  {timer_field, field} =
    case state do
      %{ac_pin: ^pin} -> {:ac_timer, :ac_ok?}
      %{bat_pin: ^pin} -> {:bat_timer, :low_battery?}
    end

  :timer.cancel(state[timer_field])
  {:ok, ref} = :timer.send_after(to_timeout(second: 1), {:update, field, value})
  {:noreply, Map.put(state, timer_field, ref)}
end
```

When the timer fires the new state is saved and an event is recorded:

```elixir
def handle_info({:update, key, value}, state) do
  state = Map.put(state, key, value)
  event = %{type: event_name(key), metadata: %{state: value}}

  with {:error, changeset} <- ExNVR.Events.create_event(event) do
    Logger.error("Failed to save event: #{inspect(changeset)}")
  end

  SystemSettings.update_setting(:monitor_power, true)
  {:noreply, %{state | publish?: true}}
end
```
