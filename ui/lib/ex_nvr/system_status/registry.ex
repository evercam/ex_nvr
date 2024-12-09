defmodule ExNVR.SystemStatus.Registry do
  @moduledoc """
  A module responsible for registering metrics and stats about the
  whole system including the hardware.
  """

  use GenServer

  alias ExNVR.SystemStatus.State

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: options[:name] || __MODULE__)
  end

  @spec get_state() :: State.t()
  def get_state() do
    GenServer.call(__MODULE__, :get_state)
  end

  @impl true
  def init(_options) do
    {:ok, %{data: %State{}}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.data, state}
  end

  @impl true
  def handle_info({:solar_charger, solar_charger_data}, state) do
    {:noreply, %{state | data: %State{solar_charger: solar_charger_data}}}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end
end
