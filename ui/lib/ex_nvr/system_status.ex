defmodule ExNVR.SystemStatus do
  @moduledoc """
  Module responsible for starting and supervising system status processes.
  """

  use GenServer

  @serial_number_file "/sys/firmware/devicetree/base/serial-number"
  @model_file "/sys/firmware/devicetree/base/model"

  @pubsub_topic "system_status"

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: options[:name] || __MODULE__)
  end

  @spec get_all(pid() | atom()) :: map()
  def get_all(pid \\ __MODULE__, timeout \\ to_timeout(second: 20)) do
    GenServer.call(pid, :get, timeout)
  end

  @spec get(atom(), pid() | atom(), timeout()) :: term()
  def get(key, pid \\ __MODULE__, timeout \\ to_timeout(second: 20)) do
    GenServer.call(pid, {:get, key}, timeout)
  end

  @spec set(atom(), any()) :: :ok
  def set(pid \\ __MODULE__, key, value) when is_atom(key) do
    GenServer.cast(pid, {:set, key, value})
  end

  @doc """
  Subscribe the calling process to system status updates.

  Subscribers receive `{:system_status, data}` messages whenever the metrics are
  refreshed (every 15s) or when an external collector sets a value via `set/3`.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(ExNVR.PubSub, @pubsub_topic)
  end

  @spec topic() :: String.t()
  def topic, do: @pubsub_topic

  @impl true
  def init(_options) do
    Process.send_after(self(), :collect_system_metrics, 0)

    {:ok, hostname} = :inet.gethostname()

    data =
      %{
        version: Application.spec(:ex_nvr, :vsn) |> to_string(),
        hostname: List.to_string(hostname),
        serial_ports: Circuits.UART.enumerate()
      }
      |> Map.merge(device_info())

    {:ok, %{data: data}}
  end

  @impl true
  def handle_call(:get, _from, state) do
    data = Map.put(state.data, :devices, ExNVR.Devices.summary())
    {:reply, data, state}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    data =
      if key == :devices do
        Map.put(state.data, :devices, ExNVR.Devices.summary())
      else
        Map.get(state.data, key)
      end

    {:reply, data, state}
  end

  @impl true
  def handle_cast({:set, key, value}, state) do
    state = put_in(state, [:data, key], value)
    emit_telemetry(key, value)
    broadcast(state.data)
    {:noreply, state}
  end

  @impl true
  def handle_info(:collect_system_metrics, state) do
    Process.send_after(self(), :collect_system_metrics, to_timeout(second: 15))
    data = do_collect_metrics(state.data)
    emit_collection_telemetry(data)
    broadcast(data)
    {:noreply, %{state | data: data}}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp do_collect_metrics(data) do
    per_core = per_core_busy()

    cpu_stats = %{
      load: [:cpu_sup.avg1(), :cpu_sup.avg5(), :cpu_sup.avg15()] |> Enum.map(&cpu_load/1),
      num_cores: length(per_core),
      per_core: per_core,
      usage: average_busy(per_core)
    }

    Map.merge(data, %{
      memory: Map.new(:memsup.get_system_memory_data()),
      cpu: cpu_stats,
      block_storage: list_block_storages()
    })
  end

  defp average_busy([]), do: 0.0

  defp average_busy(per_core) do
    Enum.sum(per_core) / length(per_core)
  end

  defp per_core_busy do
    case :cpu_sup.util([:per_cpu]) do
      cores when is_list(cores) ->
        Enum.map(cores, fn
          {_id, busy, _, _} when is_number(busy) -> busy
          _ -> 0
        end)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp cpu_load(value), do: Float.ceil(value / 256, 2)

  defp list_block_storages do
    # include MMC, SATA, USB and NVMe drives
    case ExNVR.Disk.list_drives(major_number: [8, 179, 259]) do
      {:ok, blocks} -> blocks
      _ -> []
    end
  rescue
    _error -> []
  end

  defp device_info do
    [
      {:serial_number, read_from_file(@serial_number_file)},
      {:device_model, read_from_file(@model_file)}
    ]
    |> Enum.reject(&is_nil(elem(&1, 1)))
    |> Enum.map(fn {key, value} -> {key, String.replace(value, <<0>>, "")} end)
    |> Map.new()
  end

  defp read_from_file(filename) do
    with true <- File.exists?(filename),
         {:ok, data} <- File.read(filename) do
      data
    else
      _error -> nil
    end
  end

  defp broadcast(data) do
    Phoenix.PubSub.broadcast(ExNVR.PubSub, @pubsub_topic, {:system_status, data})
  end

  defp emit_collection_telemetry(data) do
    emit_cpu(data[:cpu])
    emit_memory(data[:memory])
    Enum.each(data[:block_storage] || [], &emit_storage/1)
  end

  defp emit_cpu(%{load: [load_1m, load_5m, load_15m], num_cores: cores} = cpu) do
    :telemetry.execute(
      [:ex_nvr, :system, :cpu],
      %{
        load_1m: load_1m,
        load_5m: load_5m,
        load_15m: load_15m,
        usage: Map.get(cpu, :usage) || 0.0
      },
      %{num_cores: cores}
    )
  end

  defp emit_cpu(_), do: :ok

  defp emit_memory(mem) when is_map(mem) do
    total = mem[:total_memory] || mem[:system_total_memory] || 0
    available = mem[:available_memory] || mem[:free_memory] || 0
    used = max(total - available, 0)

    :telemetry.execute(
      [:ex_nvr, :system, :memory],
      %{used: used, total: total, available: available},
      %{}
    )
  end

  defp emit_memory(_), do: :ok

  defp emit_storage(%{name: name} = block) do
    size = Map.get(block, :size) || 0
    used = Map.get(block, :used) || 0

    :telemetry.execute(
      [:ex_nvr, :system, :storage],
      %{size: size, used: used},
      %{name: name}
    )
  end

  defp emit_storage(_), do: :ok

  defp emit_telemetry(:solar_charger, %{} = solar) do
    measurements =
      %{
        voltage_mv: Map.get(solar, :v),
        current_ma: Map.get(solar, :i),
        panel_voltage_mv: Map.get(solar, :vpv),
        panel_power_w: Map.get(solar, :ppv),
        soc: Map.get(solar, :soc)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    if map_size(measurements) > 0 do
      :telemetry.execute(
        [:ex_nvr, :system, :solar],
        measurements,
        %{serial_number: Map.get(solar, :serial_number) || "unknown"}
      )
    end
  end

  defp emit_telemetry(_key, _value), do: :ok
end
