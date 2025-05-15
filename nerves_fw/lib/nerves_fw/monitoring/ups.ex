defmodule ExNVR.Nerves.Monitoring.UPS do
  @moduledoc """
  Monitor AC and battery alarms.

  We'll use the following GPIO pins to monitor the power supply:
    * GPIO16 (input) - `1` low battery level
    * GPIO23 (input) - `0` AC failure.
  """
  require Logger

  use GenServer

  alias Circuits.GPIO
  alias ExNVR.Nerves.SystemSettings

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  # force_read? read state even if publish? is false
  def state(force_read? \\ false, pid \\ __MODULE__) do
    GenServer.call(pid, {:state, force_read?})
  end

  def reload(pid \\ __MODULE__) do
    GenServer.cast(pid, :reload)
  end

  @impl true
  def init(options) do
    ups = SystemSettings.get_settings().ups

    ac_pin = Keyword.get(options, :ac_pin, ups.ac_pin)
    bat_pin = Keyword.get(options, :battery_pin, ups.battery_pin)

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
      ups: ups
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:state, force_read?}, _from, state) do
    reply =
      if state.ups.enabled or force_read? do
        %{ac_ok?: to_bool(state.ac_ok?), low_battery?: to_bool(state.low_battery?)}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_cast(:reload, state) do
    {:noreply, %{state | ups: SystemSettings.get_settings().ups}}
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

    settings = SystemSettings.update_ups_settings(%{enabled: true})
    {:noreply, %{state | ups: settings.ups}}
  end

  @impl true
  def handle_info(message, state) do
    Logger.warning("Received unexpected message: #{inspect(message)}")
    {:noreply, state}
  end

  defp event_name(:ac_ok?), do: "power"
  defp event_name(:low_battery?), do: "low-battery"

  defp to_bool(0), do: false
  defp to_bool(_other), do: true
end
