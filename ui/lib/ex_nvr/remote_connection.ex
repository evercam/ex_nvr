defmodule ExNVR.RemoteConnection do
  @moduledoc """
  Connect to a remote server via websockets.

  The connection is intended to receive configuration from a remote server and
  to push events and health status to the server.
  """
  require Logger

  use Slipstream

  @topic "ex_nvr"
  @send_timeout to_timeout(second: 20)

  def start_link(options) do
    Slipstream.start_link(__MODULE__, options, name: __MODULE__)
  end

  @impl Slipstream
  def init(options) do
    {:ok, connect!(options)}
  end

  @impl Slipstream
  def handle_connect(socket) do
    Logger.info("Connected to remote server")
    {:ok, join(socket, @topic)}
  end

  @impl Slipstream
  def handle_join(@topic, _response, socket) do
    Logger.info("Joined topic: #{@topic}")
    {:ok, ref} = :timer.send_interval(to_timeout(minute: 1), :send_system_status)
    {:ok, assign(socket, timer_ref: ref)}
  end

  @impl Slipstream
  def handle_message(@topic, "command", %{"command" => cmd, "args" => args} = params, socket) do
    run_command(cmd, args, params["ref"])
    {:noreply, socket}
  end

  @impl Slipstream
  def handle_message(topic, event, msg, socket) do
    Logger.warning("Received unknown message: #{topic} #{event} #{inspect(msg)}")
    {:noreply, socket}
  end

  @impl Slipstream
  def handle_info(:send_system_status, socket) do
    Logger.info("Sending system status")
    push(socket, @topic, "health", ExNVR.SystemStatus.get_all(), @send_timeout)
    {:noreply, socket}
  end

  def handle_info({:command, ref, {status, payload}}, socket) do
    Logger.info("Sending command result: #{ref}")
    message = %{ref: ref, status: status, payload: payload}

    with {:error, error} <- push(socket, @topic, "command-result", message) do
      Logger.error("Error while pushing command result message: #{inspect(error)}")
    end

    {:noreply, socket}
  end

  @impl Slipstream
  def handle_info(_message, socket) do
    {:noreply, socket}
  end

  @impl Slipstream
  def handle_topic_close(topic, _reason, socket) do
    :timer.cancel(socket.assigns[:timer_ref])
    rejoin(assign(socket, timer_ref: nil), topic)
  end

  @impl Slipstream
  def handle_disconnect(_reason, socket) do
    :timer.cancel(socket.assigns[:timer_ref])
    reconnect(socket)
  end

  defp run_command(cmd, args, ref) do
    pid = self()

    spawn(fn ->
      result =
        try do
          case System.cmd(cmd, args) do
            {output, 0} -> {:ok, output}
            {output, _status} -> {:error, output}
          end
        rescue
          exception ->
            Logger.error("""
            Error running command: #{cmd}
            #{inspect(exception)}
            """)

            {:error, Exception.message(exception)}
        end

      send(pid, {:command, ref, result})
    end)
  end
end
