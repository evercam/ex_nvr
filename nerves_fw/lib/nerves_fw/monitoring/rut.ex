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

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec state() :: map()
  def state() do
    GenServer.call(__MODULE__, :state)
  end

  @impl true
  def init(opts) do
    modbux_opts = Keyword.take(opts, [:ip, :port, :timeout]) |> Keyword.put(:active, false)
    {:ok, modbus_pid} = Client.start_link(modbux_opts)

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
    case Client.connect(state.modbus_pid) do
      :ok -> Process.send_after(self(), :send_requests, 0)
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

        value =
          Enum.reject(values, &(&1 == 0))
          |> Enum.flat_map(&[&1 >>> 8, &1 &&& 0xFF])
          |> List.to_string()

        {name, value}
      end)

    send(state.registry, {:router, data})
    Process.send_after(self(), :send_requests, @request_interval)

    {:noreply, %{state | data: data}}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end
end
