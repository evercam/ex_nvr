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
    {:ok, timer_ref} = :timer.send_interval(:timer.seconds(15), :collect_metrics)
    {:ok, %{data: %State{}, timer: timer_ref}}
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
  def handle_info(:collect_metrics, %{data: data} = state) do
    cpu_stats = %{
      load_avg:
        {cpu_load(:cpu_sup.avg1()), cpu_load(:cpu_sup.avg5()), cpu_load(:cpu_sup.avg15())},
      num_cores: :cpu_sup.util([:detailed]) |> elem(0) |> length()
    }

    data = %State{data | memory: Map.new(:memsup.get_system_memory_data()), cpu: cpu_stats}
    {:noreply, %{state | data: data}}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    :timer.cancel(state.timer)
  end

  defp cpu_load(value), do: Float.ceil(value / 256, 2)
end
