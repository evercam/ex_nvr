defmodule ExNVR.Nerves.Monitoring.RUT do
  @moduledoc """
  Get basic data from Teltonika routers.

  The communication is done via MODBUS.

  The following router's models are supported:
    * RUT23x
    * RUT24x
    * RUT95x
    * RUTX11
  """

  use GenServer

  import Bitwise

  alias Modbux.Tcp.Client

  @connect_interval :timer.seconds(30)
  @request_interval :timer.minutes(1)

  @requests %{
    serial_number: {:rhr, 0x1, 39, 16},
    mac_address: {:rhr, 0x1, 55, 16},
    name: {:rhr, 0x1, 71, 16}
  }

  def start_link(registry) do
    GenServer.start_link(__MODULE__, [registry: registry], name: __MODULE__)
  end

  @spec state() :: map()
  def state() do
    GenServer.call(__MODULE__, :state)
  end

  @impl true
  def init(opts) do
    {:ok, modbus_pid} = Client.start_link(active: false, timeout: :timer.seconds(5))

    state = %{
      modbus_pid: modbus_pid,
      registry: opts[:registry],
      data: Map.new(@requests, fn {key, _value} -> {key, nil} end)
    }

    Process.send_after(self(), :connect, 0)

    {:ok, state}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, state.data, state}
  end

  @impl true
  def handle_info(:connect, state) do
    with {:ok, gateway} <- get_default_gateway(),
         :ok <- Client.configure(state.modbus_pid, ip: gateway),
         :ok <- Client.connect(state.modbus_pid) do
      Process.send_after(self(), :send_requests, 0)
    else
      _error -> Process.send_after(self(), :connect, @connect_interval)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:send_requests, state) do
    data =
      Map.new(@requests, fn {name, req} ->
        :ok = Client.request(state.modbus_pid, req)
        {:ok, values} = Client.confirmation(state.modbus_pid)

        {name, map_values(name, values)}
      end)

    send(state.registry, {:router, data})
    Process.send_after(self(), :send_requests, @request_interval)

    {:noreply, %{state | data: data}}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp get_default_gateway() do
    case System.cmd("ip", ["route"], stderr_to_stdout: true) do
      {output, 0} ->
        String.split(output, "\n")
        |> Enum.find("", &String.starts_with?(&1, "default"))
        |> String.split(" ")
        |> case do
          ["default", "via", gateway | _rest] -> :inet.parse_address(to_charlist(gateway))
          _other -> {:error, :no_gateway}
        end

      {error, _exit_status} ->
        {:error, error}
    end
  end

  defp map_values(:mac_address, values) do
    Enum.take(values, 6)
    |> Enum.map(&[&1 >>> 8, &1 &&& 0xFF])
    |> List.to_string()
  end

  defp map_values(_field, values) do
    Enum.reject(values, &(&1 == 0))
    |> Enum.map(&[&1 >>> 8, &1 &&& 0xFF])
    |> List.to_string()
  end
end
