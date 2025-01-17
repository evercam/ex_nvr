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

  @spec get_state(pid() | atom() | nil) :: State.t()
  def get_state(server \\ nil) do
    GenServer.call(server || __MODULE__, :get_state)
  end

  @impl true
  def init(options) do
    {:ok, timer_ref} =
      :timer.send_interval(options[:interval] || :timer.seconds(15), :collect_metrics)

    {:ok,
     %{
       data: do_collect_metrics(%State{version: Application.spec(:ex_nvr, :vsn) |> to_string()}),
       timer: timer_ref
     }}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.data, state}
  end

  @impl true
  def handle_info({:solar_charger, solar_charger_data}, state) do
    {:noreply, %{state | data: %State{state.data | solar_charger: solar_charger_data}}}
  end

  @impl true
  def handle_info({:router, router_data}, state) do
    {:noreply, %{state | data: %State{state.data | router: router_data}}}
  end

  @impl true
  def handle_info(:collect_metrics, %{data: data} = state) do
    {:noreply, %{state | data: do_collect_metrics(data)}}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    :timer.cancel(state.timer)
    :ok
  end

  defp do_collect_metrics(data) do
    cpu_stats = %{
      load: [:cpu_sup.avg1(), :cpu_sup.avg5(), :cpu_sup.avg15()] |> Enum.map(&cpu_load/1),
      num_cores: :cpu_sup.util([:detailed]) |> elem(0) |> length()
    }

    %State{
      data
      | memory: Map.new(:memsup.get_system_memory_data()),
        cpu: cpu_stats,
        block_storage: list_block_storages()
    }
  end

  defp cpu_load(value), do: Float.ceil(value / 256, 2)

  defp list_block_storages() do
    # include MMC, SATA, USB and NVMe drives
    case ExNVR.Disk.list_drives(major_number: [8, 179, 259]) do
      {:ok, blocks} -> blocks
      _ -> []
    end
  end
end
