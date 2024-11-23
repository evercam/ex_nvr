defmodule ExNVR.UnixSocketServer do
  @moduledoc """
  A unix socket server that serves snapshots over unix socket.

  Only available on unix systems
  """

  use GenServer

  require Logger

  alias ExNVR.Utils

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    Process.send_after(self(), :connect, 0)
    device = opts[:device]
    {:ok, %{path: Utils.unix_socket_path(device.id), device: device, socket: nil}}
  end

  @impl true
  def handle_info(:connect, state) do
    File.rm(state.path)

    case :gen_tcp.listen(0, [:binary, ifaddr: {:local, to_charlist(state.path)}, active: false]) do
      {:ok, socket} ->
        Process.send_after(self(), :listen, 0)
        {:noreply, %{state | socket: socket}}

      {:error, error} ->
        Logger.error("""
        UnixSocketServer: could not listen on unix socket #{state.path}
        #{inspect(error)}
        """)

        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:listen, state) do
    with {:ok, client_socket} <- :gen_tcp.accept(state.socket) do
      send(Utils.pipeline_name(state.device), {:new_socket, client_socket})
    end

    Process.send_after(self(), :listen, 0)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
