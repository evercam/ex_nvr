defmodule ExNVR.SystemStatus do
  @moduledoc """
  Module responsible for starting and supervising system status processes.
  """

  use GenServer

  @serial_number_file "/sys/firmware/devicetree/base/serial-number"
  @model_file "/sys/firmware/devicetree/base/model"

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
    {:noreply, put_in(state, [:data, key], value)}
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
  rescue
    _error -> []
  end

  defp device_info() do
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
end
