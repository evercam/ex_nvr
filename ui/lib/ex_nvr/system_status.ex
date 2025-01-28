defmodule ExNVR.SystemStatus do
  @moduledoc """
  Module responsible for starting and supervising system status processes.
  """

  use GenServer

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: options[:name] || __MODULE__)
  end

  @spec get(pid() | atom()) :: map()
  def get(pid \\ __MODULE__) do
    GenServer.call(pid, :get)
  end

  @spec set(atom(), any()) :: :ok
  def set(pid \\ __MODULE__, key, value) when is_atom(key) do
    GenServer.call(pid, {:set, key, value})
  end

  @doc """
  Handle telemetry events: `[:system, :status, key]`.
  """
  @spec register(atom()) :: :ok
  def register(pid \\ __MODULE__, key) do
    GenServer.call(pid, {:register, key})
  end

  @impl true
  def init(_options) do
    Process.send_after(self(), :collect_system_metrics, 0)

    {:ok, hostname} = :inet.gethostname()

    data = %{
      version: Application.spec(:ex_nvr, :vsn) |> to_string(),
      hostname: List.to_string(hostname)
    }

    {:ok, %{data: data}}
  end

  @impl true
  def handle_call(:get, _from, state) do
    data = Map.put(state.data, :devices, ExNVR.Devices.summary())
    {:reply, data, state}
  end

  @impl true
  def handle_call({:set, key, value}, _from, state) do
    {:reply, :ok, put_in(state, [:data, key], value)}
  end

  @impl true
  def handle_call({:register, key}, _from, state) do
    :telemetry.attach("system-status-#{key}", [:system, :status, key], &__MODULE__.handle_event/4, self())
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:collect_system_metrics, state) do
    Process.send_after(self(), :collect_system_metrics, to_timeout(second: 15))
    {:noreply, %{state | data: do_collect_metrics(state.data)}}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end

  def handle_event([:system, :status, key], %{value: data}, _metadata, pid) do
    __MODULE__.set(pid, key, data)
  end

  defp do_collect_metrics(data) do
    cpu_stats = %{
      load: [:cpu_sup.avg1(), :cpu_sup.avg5(), :cpu_sup.avg15()] |> Enum.map(&cpu_load/1),
      num_cores: :cpu_sup.util([:detailed]) |> elem(0) |> length()
    }

    Map.merge(data, %{
      memory: Map.new(:memsup.get_system_memory_data()),
      cpu: cpu_stats,
      block_storage: list_block_storages()
    })
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
