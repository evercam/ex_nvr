defmodule ExNVR.QemuTest.QMP do
  @moduledoc """
  A tiny QEMU Machine Protocol (QMP) client.

  QMP is the control plane we use to inject faults from *outside* the guest:
  disk I/O throttling, network packet filters, balloon-driven memory pressure,
  resets and power loss. It is a line-delimited JSON protocol over a socket.

  Usage:

      {:ok, qmp} = QMP.connect(4444)
      {:ok, _} = QMP.execute(qmp, "block_set_io_throttle", %{
        device: "vdata", bps: 0, bps_rd: 1_048_576, bps_wr: 0,
        iops: 0, iops_rd: 0, iops_wr: 0
      })
  """

  @enforce_keys [:socket]
  defstruct [:socket]

  @type t :: %__MODULE__{socket: port()}

  @doc """
  Connect to a QMP TCP port, read the greeting and negotiate capabilities.
  """
  @spec connect(:inet.port_number(), keyword()) :: {:ok, t()} | {:error, term()}
  def connect(port, opts \\ []) do
    host = Keyword.get(opts, :host, {127, 0, 0, 1})
    timeout = Keyword.get(opts, :timeout, 5_000)

    with {:ok, socket} <-
           :gen_tcp.connect(host, port, [:binary, packet: :line, active: false], timeout),
         {:ok, _greeting} <- recv_json(socket, timeout) do
      qmp = %__MODULE__{socket: socket}
      # Leave "negotiation" mode so normal commands are accepted.
      case execute(qmp, "qmp_capabilities") do
        {:ok, _} -> {:ok, qmp}
        error -> error
      end
    end
  end

  @doc """
  Execute a QMP command with optional arguments, returning `{:ok, result}` or
  `{:error, qmp_error}`. Async events that arrive first are skipped.
  """
  @spec execute(t(), String.t(), map(), timeout()) :: {:ok, term()} | {:error, term()}
  def execute(%__MODULE__{socket: socket}, command, arguments \\ %{}, timeout \\ 10_000) do
    payload = %{execute: command}
    payload = if map_size(arguments) > 0, do: Map.put(payload, :arguments, arguments), else: payload

    case :gen_tcp.send(socket, [JSON.encode!(payload), "\n"]) do
      :ok -> wait_response(socket, timeout)
      error -> error
    end
  end

  @doc """
  Like `execute/4` but raises on error. Returns the result map.
  """
  @spec execute!(t(), String.t(), map(), timeout()) :: term()
  def execute!(qmp, command, arguments \\ %{}, timeout \\ 10_000) do
    case execute(qmp, command, arguments, timeout) do
      {:ok, result} -> result
      {:error, reason} -> raise "QMP #{command} failed: #{inspect(reason)}"
    end
  end

  @doc "Close the QMP socket."
  @spec close(t()) :: :ok
  def close(%__MODULE__{socket: socket}), do: :gen_tcp.close(socket)

  @doc """
  Block until a QMP event named `name` arrives, or `timeout` elapses. Returns
  `{:ok, event}` or `{:error, :timeout}`. Used to observe a guest-initiated
  reset/reboot (the QMP `RESET` event) - e.g. the watchdog rebooting the device.
  """
  @spec wait_event(t(), String.t(), timeout()) :: {:ok, map()} | {:error, term()}
  def wait_event(%__MODULE__{socket: socket}, name, timeout \\ 60_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_event(socket, name, deadline)
  end

  defp do_wait_event(socket, name, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, :timeout}
    else
      case recv_json(socket, remaining) do
        {:ok, %{"event" => ^name} = event} -> {:ok, event}
        {:ok, _other} -> do_wait_event(socket, name, deadline)
        {:error, :timeout} -> {:error, :timeout}
        {:error, _} = error -> error
      end
    end
  end

  defp wait_response(socket, timeout) do
    case recv_json(socket, timeout) do
      {:ok, %{"return" => result}} -> {:ok, result}
      {:ok, %{"error" => error}} -> {:error, error}
      # Greeting and async events: keep waiting for the command response.
      {:ok, %{"QMP" => _}} -> wait_response(socket, timeout)
      {:ok, %{"event" => _}} -> wait_response(socket, timeout)
      {:ok, other} -> {:ok, other}
      {:error, _} = error -> error
    end
  end

  defp recv_json(socket, timeout) do
    case :gen_tcp.recv(socket, 0, timeout) do
      {:ok, line} -> {:ok, JSON.decode!(line)}
      {:error, _} = error -> error
    end
  end
end
