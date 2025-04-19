defmodule ExNVR.Nerves.Monitoring.Power do
  @moduledoc """
  Monitor AC and battery alarms.

  We'll use the following GPIO pins to monitor the power supply:
    * GPIO16 (input) - `1` low battery level
    * GPIO23 (input) - `0` AC failure.
  """
  require Logger

  use GenServer

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  def state(pid \\ __MODULE__) do
    GenServer.call(pid, :state)
  end

  @impl true
  def init(options) do
    ac_pin = Keyword.get(options, :ac_pin, "GPIO23")
    bat_pin = Keyword.get(options, :battery_pin, "GPIO16")

    {:ok, ac_gpio} = Circuits.GPIO.open(ac_pin, :input)
    {:ok, bat_gpio} = Circuits.GPIO.open(bat_pin, :input)

    :ok = Circuits.GPIO.set_pull_mode(bat_gpio, :pulldown)
    :ok = Circuits.GPIO.set_pull_mode(ac_gpio, :pulldown)

    # Set up event handlers
    :ok = Circuits.GPIO.set_interrupts(bat_gpio, :both)
    :ok = Circuits.GPIO.set_interrupts(ac_gpio, :both)

    state = %{
      ac_pin: ac_pin,
      bat_pin: bat_pin,
      ac_gpio: ac_gpio,
      bat_gpio: bat_gpio,
      ac_timer: nil,
      bat_timer: nil,
      ac_ok?: Circuits.GPIO.read(ac_gpio),
      low_battery?: Circuits.GPIO.read(bat_gpio)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, Map.take(state, [:ac_ok?, :low_battery?]), state}
  end

  @impl true
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

  @impl true
  def handle_info({:update, :ac_ok?, value}, %{ac_ok?: value} = state), do: {:noreply, state}

  @impl true
  def handle_info({:update, :low_battery?, value}, %{low_battery?: value} = state),
    do: {:noreply, state}

  @impl true
  def handle_info({:update, key, value}, state) do
    state = Map.put(state, key, value)
    event = %{type: event_name(key), metadata: %{state: value}}

    with {:error, changeset} <- ExNVR.Events.create_event(event) do
      Logger.error("Failed to save event: #{inspect(changeset)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(message, state) do
    Logger.warning("Received unexpected message: #{inspect(message)}")
    {:noreply, state}
  end

  defp event_name(:ac_ok?), do: "power"
  defp event_name(:low_battery?), do: "low-battery"
end
