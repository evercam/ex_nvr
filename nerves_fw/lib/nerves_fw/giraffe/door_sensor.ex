defmodule ExNVR.Nerves.Giraffe.DoorSensor do
  @moduledoc """
  Monitor the kit door state.

  Low = closed, high = open.
  """

  use GenServer

  require Logger

  alias ExNVR.Nerves.GPIO
  alias ExNVR.Nerves.SystemStatus

  # TODO: placeholder pin, pending hardware confirmation. Currently conflicts
  # with the generator monitor opened on GPIO10 by ExNVR.Nerves.Giraffe.Init.
  @door_pin "GPIO10"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def state(pid \\ __MODULE__) do
    GenServer.call(pid, :state)
  end

  @impl true
  def init(opts) do
    :ok = SystemStatus.set(:door, :unknown)
    {:ok, %{pin: Keyword.get(opts, :pin, @door_pin)}, {:continue, :init}}
  end

  @impl true
  def handle_continue(:init, state) do
    {:ok, door_pid} = GPIO.start_link(pin: state.pin)
    state = Map.put(state, :door, door_pid)
    :ok = SystemStatus.set(:door, door_state(GPIO.value(door_pid)))
    {:noreply, state}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, door_state(GPIO.value(state.door)), state}
  end

  @impl true
  def handle_info({door_pid, value}, %{door: door_pid} = state) do
    new_state = door_state(value)
    :ok = SystemStatus.set(:door, new_state)

    with {:error, changeset} <-
           ExNVR.Events.create_event(%{type: "door", metadata: %{state: new_state}}) do
      Logger.error("[DoorSensor] failed to save event: #{inspect(changeset)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp door_state(0), do: :closed
  defp door_state(1), do: :open
  defp door_state(_), do: :unknown
end
