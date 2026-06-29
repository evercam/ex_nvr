defmodule ExNVR.Nerves.GPIO do
  @moduledoc """
  Monitor GPIO pins for state changes.
  """

  use GenServer

  alias Circuits.GPIO

  def start_link(options) do
    options = Keyword.put_new(options, :receiver, self())

    GenServer.start_link(__MODULE__, options,
      name: options[:name],
      spawn_opt: [fullsweep_after: 0]
    )
  end

  def value(pid) do
    GenServer.call(pid, :value)
  end

  @impl true
  def init(options) do
    Process.set_label({:gpio, options[:pin]})

    {:ok, gpio} = GPIO.open(options[:pin], :input, pull_mode: :pulldown)
    :ok = GPIO.set_interrupts(gpio, :both)
    {:ok, %{value: GPIO.read(gpio), gpio: gpio, timer: nil, receiver: options[:receiver]}}
  end

  @impl true
  def handle_call(:value, _from, state) do
    {:reply, state.value, state}
  end

  @impl true
  def handle_info({:circuits_gpio, _pin, _timestamp, value}, state) do
    # Timer used for debounce
    # We need to wait for the signal to stabilize before reading it.
    :timer.cancel(state[:timer])
    {:ok, ref} = :timer.send_after(to_timeout(second: 1), {:update, value})
    {:noreply, %{state | timer: ref}}
  end

  @impl true
  def handle_info({:update, value}, %{value: value} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:update, value}, state) do
    send(state.receiver, {self(), value})
    {:noreply, %{state | value: value}}
  end
end
