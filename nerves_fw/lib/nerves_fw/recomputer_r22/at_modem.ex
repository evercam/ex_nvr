defmodule ExNVR.Nerves.RecomputerR22.ATModem do
  @moduledoc """
  GenServer for sending AT commands to a 4G modem via serial and parsing responses.

  Commands are queued and dispatched one at a time. Responses are parsed into
  structured maps for common commands (+CSQ, +CREG, +CEREG, +COPS, +CPIN, etc.).
  Unsolicited result codes (URCs) are logged and discarded unless a URC handler
  is registered.
  """

  use GenServer

  require Logger

  alias Circuits.UART

  @default_device "/dev/ttyUSB2"
  @default_speed 115_200
  @default_timeout 5_000

  @reboot_timeout 90_000
  @poll_interval 500
  @ping_interval 1_000

  @final_codes ~w(OK ERROR CONNECT NO\ CARRIER BUSY NO\ ANSWER NO\ DIALTONE)

  @usbnet_modes %{0 => :qmi, 1 => :ecm, 2 => :mbim, 3 => :rndis}
  @usbnet_values Map.new(@usbnet_modes, fn {value, mode} -> {mode, value} end)

  def start_link(opts \\ []) do
    case GenServer.start_link(__MODULE__, opts, name: __MODULE__) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, _reason} = error -> error
    end
  end

  def start(opts \\ []) do
    case GenServer.start(__MODULE__, opts, name: __MODULE__) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, _reason} = error -> error
    end
  end

  def send_command(command, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(__MODULE__, {:send_command, command}, timeout + 1_000)
  end

  def close, do: GenServer.call(__MODULE__, :close)

  def reconnect, do: GenServer.call(__MODULE__, :reconnect)

  def ping, do: send_command("AT")

  def identify, do: send_command("ATI")

  def manufacturer, do: send_command("AT+CGMI")

  def model, do: send_command("AT+CGMM")

  def firmware_version, do: send_command("AT+CGMR")

  def imei, do: send_command("AT+CGSN")

  def imsi, do: send_command("AT+CIMI")

  def iccid, do: send_command("AT+ICCID")

  # SIM / network status
  def sim_status, do: send_command("AT+CPIN?")

  def signal_quality, do: send_command("AT+CSQ")

  def network_registration, do: send_command("AT+CREG?")

  def eps_registration, do: send_command("AT+CEREG?")

  def operator, do: send_command("AT+COPS?")

  def scan_operators, do: send_command("AT+COPS=?", timeout: 60_000)

  def pdp_contexts, do: send_command("AT+CGDCONT?")

  def set_pdp_context(cid, type \\ "IP", apn),
    do: send_command("AT+CGDCONT=#{cid},\"#{type}\",\"#{apn}\"")

  def context_states, do: send_command("AT+CGACT?")

  def activate_context(cid), do: send_command("AT+CGACT=1,#{cid}")

  def deactivate_context(cid), do: send_command("AT+CGACT=0,#{cid}")

  # SMS
  def set_sms_format(n \\ 1), do: send_command("AT+CMGF=#{n}")

  def list_sms(stat \\ "ALL"), do: send_command("AT+CMGL=\"#{stat}\"", timeout: 15_000)

  def read_sms(index), do: send_command("AT+CMGR=#{index}")

  def delete_sms(index), do: send_command("AT+CMGD=#{index}")

  # Control
  def set_error_format(n \\ 2), do: send_command("AT+CMEE=#{n}")

  def set_functionality(fun \\ 1), do: send_command("AT+CFUN=#{fun}")

  def functionality, do: send_command("AT+CFUN?")

  @doc """
  Reboot the modem and block until it has come back up.

  Returns `:ok` once the modem is reachable again, or `{:error, reason}` if it
  does not come back within `timeout` (default #{@reboot_timeout}ms).
  """
  def reboot(timeout \\ @reboot_timeout) do
    GenServer.call(__MODULE__, {:reboot, timeout}, timeout + 5_000)
  end

  def factory_reset, do: send_command("AT&F")

  def reset, do: send_command("ATZ")

  def pdp_address(cid \\ 1), do: send_command("AT+CGPADDR=#{cid}")

  # USB network mode (Quectel `AT+QCFG="usbnet"`). Modes: :qmi | :ecm | :mbim | :rndis.
  # The reComputer R22 expects a usbnet (CDC ECM) interface rather than a QMI
  # device, so VintageNet can manage it as a regular ethernet interface.

  @doc "Return the current USB network mode as `{:ok, mode}` or `{:error, reason}`."
  def usbnet_mode do
    case send_command(~s(AT+QCFG="usbnet")) do
      {:ok, %{usbnet: mode}} -> {:ok, mode}
      {:ok, other} -> {:error, {:unexpected_response, other}}
      {:error, _} = error -> error
    end
  end

  @doc "Set the USB network mode (atom or raw integer). A reboot is needed to apply it."
  def set_usbnet_mode(mode) when is_atom(mode),
    do: set_usbnet_mode(Map.fetch!(@usbnet_values, mode))

  def set_usbnet_mode(mode) when is_integer(mode), do: send_command(~s(AT+QCFG="usbnet",#{mode}))

  # Connectivity checks (bypass AT queue — direct TCP via Erlang socket API)

  @doc """
  Check internet reachability through a specific network interface (e.g. `"wwan0"`).

  Looks up the interface's current IP address via `:inet.getifaddrs/0` and binds
  the TCP socket to it, ensuring traffic goes through the modem rather than any
  other interface the OS routing table might prefer.

  Tries 8.8.8.8, 1.1.1.1 and 9.9.9.9 on port 53 in sequence; returns `:ok` on
  the first success, `{:error, reason}` otherwise.
  """
  def check_internet(interface, timeout \\ 5_000) do
    with {:ok, local_ip} <- interface_ip(interface) do
      hosts = [{8, 8, 8, 8}, {1, 1, 1, 1}, {9, 9, 9, 9}]

      if Enum.any?(hosts, &tcp_reachable?(&1, 53, [ip: local_ip], timeout)),
        do: :ok,
        else: {:error, :unreachable}
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    device = Keyword.get(opts, :device, @default_device)
    speed = Keyword.get(opts, :speed, @default_speed)
    {:ok, uart} = UART.start_link()

    state = %{
      uart: uart,
      device: device,
      speed: speed,
      pending: nil,
      queue: :queue.new(),
      reboot: nil
    }

    case UART.open(uart, device, open_opts(state)) do
      :ok ->
        Logger.info("ATModem: connected to #{device}")
        {:ok, state}

      {:error, reason} ->
        Logger.error("ATModem: failed to open #{device}: #{inspect(reason)}")
        GenServer.stop(uart)
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:send_command, _command}, _from, %{reboot: reboot} = state)
      when reboot != nil do
    {:reply, {:error, :reboot_in_progress}, state}
  end

  def handle_call({:send_command, command}, from, state) do
    queue = :queue.in({:cmd, command, from}, state.queue)
    {:noreply, maybe_dispatch(%{state | queue: queue})}
  end

  def handle_call(:close, _from, state) do
    {:stop, :normal, UART.close(state.uart), flush_pending(state)}
  end

  def handle_call(:reconnect, _from, state) do
    UART.close(state.uart)
    state = flush_pending(state)

    case UART.open(state.uart, state.device, open_opts(state)) do
      :ok ->
        Logger.info("ATModem: reconnected to #{state.device}")
        {:reply, :ok, state}

      {:error, reason} = error ->
        Logger.error("ATModem: reconnect failed: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call({:reboot, _timeout}, _from, %{reboot: reboot} = state) when reboot != nil do
    {:reply, {:error, :reboot_in_progress}, state}
  end

  def handle_call({:reboot, timeout}, from, state) do
    state = flush_pending(state)
    UART.write(state.uart, "AT+CFUN=1,1\r\n")
    UART.close(state.uart)

    %{uart: uart, device: device, speed: speed} = state
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        send(parent, {:reboot_done, self(), do_reboot(uart, device, speed, timeout)})
      end)

    {:noreply, %{state | reboot: %{from: from, pid: pid, ref: ref}}}
  end

  @impl true
  def handle_info({:circuits_uart, _port, data}, state) do
    {:noreply, process_line(state, String.trim(data))}
  end

  def handle_info(
        {:reboot_done, pid, result},
        %{reboot: %{pid: pid, ref: ref, from: from}} = state
      ) do
    Process.demonitor(ref, [:flush])
    {:noreply, finish_reboot(state, from, result)}
  end

  def handle_info(
        {:DOWN, ref, :process, pid, reason},
        %{reboot: %{pid: pid, ref: ref, from: from}} = state
      ) do
    {:noreply, finish_reboot(state, from, {:error, {:reboot_task_crashed, reason}})}
  end

  def handle_info(:command_timeout, %{pending: {:cmd, from, _timer, _lines}} = state) do
    Logger.warning("ATModem: command timed out")
    GenServer.reply(from, {:error, :timeout})
    {:noreply, maybe_dispatch(%{state | pending: nil})}
  end

  def handle_info(:command_timeout, state), do: {:noreply, state}

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp open_opts(state) do
    [speed: state.speed, active: true, framing: {UART.Framing.Line, separator: "\r\n"}]
  end

  # Reply to the reboot caller and clear the reboot state. On success the UART
  # was closed by the task, so reopen it in active mode for normal operation.
  defp finish_reboot(state, from, result) do
    state =
      case result do
        :ok ->
          Logger.info("ATModem: rebooted and reconnected to #{state.device}")
          reopen(state)

        {:error, reason} ->
          Logger.error("ATModem: reboot failed: #{inspect(reason)}")
          state
      end

    GenServer.reply(from, result)
    %{state | reboot: nil}
  end

  defp reopen(state) do
    case UART.open(state.uart, state.device, open_opts(state)) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("ATModem: failed to reopen #{state.device}: #{inspect(reason)}")
    end

    state
  end

  # Runs in the spawned reboot task. Waits for the serial node to disappear and
  # re-appear, then reopens (passively) and polls AT until the modem answers OK.
  # Closes the UART before returning so the GenServer can reopen it in active mode.
  defp do_reboot(uart, device, speed, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    opts = [speed: speed, active: false, framing: {UART.Framing.Line, separator: "\r\n"}]

    result =
      with :ok <- wait_until(deadline, :reboot_not_detected, fn -> not File.exists?(device) end),
           :ok <- wait_until(deadline, :device_not_back, fn -> File.exists?(device) end) do
        open_and_ping(uart, device, opts, deadline)
      end

    UART.close(uart)
    result
  end

  # Poll `fun` every @poll_interval until it returns true or the deadline passes.
  defp wait_until(deadline, error_reason, fun) do
    cond do
      fun.() ->
        :ok

      past_deadline?(deadline) ->
        {:error, error_reason}

      true ->
        Process.sleep(@poll_interval)
        wait_until(deadline, error_reason, fun)
    end
  end

  # Reopen the UART (retrying while the node settles) then ping until responsive.
  defp open_and_ping(uart, device, opts, deadline) do
    case UART.open(uart, device, opts) do
      :ok ->
        ping(uart, deadline)

      {:error, reason} ->
        if past_deadline?(deadline) do
          {:error, reason}
        else
          Process.sleep(@poll_interval)
          open_and_ping(uart, device, opts, deadline)
        end
    end
  end

  defp ping(uart, deadline) do
    UART.write(uart, "AT\r\n")
    read_response(uart, deadline)
  end

  # Read framed lines (passive mode) until we see "OK"; re-send AT on idle gaps.
  defp read_response(uart, deadline) do
    if past_deadline?(deadline) do
      {:error, :unresponsive}
    else
      uart |> UART.read(@ping_interval) |> handle_read(uart, deadline)
    end
  end

  defp handle_read({:ok, ""}, uart, deadline), do: ping(uart, deadline)
  defp handle_read({:error, _reason}, uart, deadline), do: ping(uart, deadline)

  defp handle_read({:ok, data}, uart, deadline) do
    if String.contains?(data, "OK"), do: :ok, else: read_response(uart, deadline)
  end

  defp past_deadline?(deadline), do: System.monotonic_time(:millisecond) >= deadline

  defp flush_pending(state) do
    case state.pending do
      nil ->
        :ok

      {:cmd, from, timer, _} ->
        Process.cancel_timer(timer)
        GenServer.reply(from, {:error, :closed})
    end

    Enum.each(:queue.to_list(state.queue), fn
      {:cmd, _cmd, from} -> GenServer.reply(from, {:error, :closed})
    end)

    %{state | pending: nil, queue: :queue.new()}
  end

  defp maybe_dispatch(%{pending: nil} = state) do
    case :queue.out(state.queue) do
      {{:value, {:cmd, command, from}}, queue} ->
        UART.write(state.uart, command <> "\r\n")
        timer = Process.send_after(self(), :command_timeout, @default_timeout)
        %{state | pending: {:cmd, from, timer, []}, queue: queue}

      {:empty, _} ->
        state
    end
  end

  defp maybe_dispatch(state), do: state

  defp process_line(state, ""), do: state

  defp process_line(%{pending: nil} = state, line) do
    Logger.debug("ATModem URC: #{line}")
    state
  end

  # Standard command — waiting for a final result code.
  defp process_line(%{pending: {:cmd, from, timer, lines}} = state, line) do
    if final_code?(line) do
      Process.cancel_timer(timer)
      GenServer.reply(from, build_result(lines, line))
      maybe_dispatch(%{state | pending: nil})
    else
      updated = if String.starts_with?(line, "AT"), do: lines, else: lines ++ [line]
      %{state | pending: {:cmd, from, timer, updated}}
    end
  end

  defp final_code?(line) do
    Enum.any?(@final_codes, &String.starts_with?(line, &1)) or
      String.match?(line, ~r/^\+CME ERROR:/) or
      String.match?(line, ~r/^\+CMS ERROR:/)
  end

  defp build_result(response_lines, final) do
    case final do
      "OK" ->
        {:ok, parse_response(response_lines)}

      <<"CONNECT", _::binary>> ->
        {:ok, :connected}

      "NO CARRIER" ->
        {:error, :no_carrier}

      "BUSY" ->
        {:error, :busy}

      "NO ANSWER" ->
        {:error, :no_answer}

      "NO DIALTONE" ->
        {:error, :no_dialtone}

      <<"ERROR">> ->
        {:error, :error}

      <<"+CME ERROR:", rest::binary>> ->
        {:error, {:cme_error, String.trim(rest)}}

      <<"+CMS ERROR:", rest::binary>> ->
        {:error, {:cms_error, String.trim(rest)}}

      _ ->
        {:error, :error}
    end
  end

  defp parse_response([]), do: :ok
  defp parse_response([line]), do: parse_line(line)
  defp parse_response(lines), do: Enum.map(lines, &parse_line/1)

  defp parse_line(<<"+CSQ: ", rest::binary>>) do
    [rssi, ber] = String.split(rest, ",")
    %{rssi: to_int(rssi), ber: to_int(ber)}
  end

  defp parse_line(<<"+CREG: ", rest::binary>>) do
    rest |> split_csv() |> parse_reg_status()
  end

  defp parse_line(<<"+CEREG: ", rest::binary>>) do
    rest |> split_csv() |> parse_reg_status()
  end

  defp parse_line(<<"+COPS: ", rest::binary>>) do
    case split_csv(rest) do
      [mode, format, oper | tail] ->
        %{
          mode: to_int(mode),
          format: to_int(format),
          operator: unquote_str(oper),
          act: act_from_list(tail)
        }

      [mode] ->
        %{mode: to_int(mode)}
    end
  end

  defp parse_line(<<"+CPIN: ", rest::binary>>), do: %{sim: String.trim(rest)}

  defp parse_line(<<"+CFUN: ", rest::binary>>), do: %{fun: to_int(rest)}

  defp parse_line(<<"+CGDCONT: ", rest::binary>>) do
    case String.split(rest, ",", parts: 4) do
      [cid, type, apn | _] -> %{cid: to_int(cid), type: unquote_str(type), apn: unquote_str(apn)}
      _ -> rest
    end
  end

  defp parse_line(<<"+CGACT: ", rest::binary>>) do
    case split_csv(rest) do
      [cid, state] -> %{cid: to_int(cid), active: to_int(state) == 1}
      _ -> rest
    end
  end

  defp parse_line(<<"+CMGL: ", rest::binary>>) do
    case split_csv(rest) do
      [index, status, alpha, length] ->
        %{
          index: to_int(index),
          status: unquote_str(status),
          alpha: unquote_str(alpha),
          length: to_int(length)
        }

      _ ->
        rest
    end
  end

  defp parse_line(<<"+ICCID: ", rest::binary>>), do: String.trim(rest)

  defp parse_line(<<"+QCFG: ", rest::binary>>) do
    case split_csv(rest) do
      ["\"usbnet\"", mode | _] -> %{usbnet: Map.get(@usbnet_modes, to_int(mode), :unknown)}
      _ -> rest
    end
  end

  defp parse_line(line), do: line

  defp parse_reg_status([stat]) do
    %{stat: reg_status(to_int(stat))}
  end

  defp parse_reg_status([_n, stat]) do
    %{stat: reg_status(to_int(stat))}
  end

  defp parse_reg_status([_n, stat, lac, ci | tail]) do
    %{stat: reg_status(to_int(stat)), lac: lac, ci: ci, act: act_from_list(tail)}
  end

  defp parse_reg_status(_), do: %{}

  defp reg_status(0), do: :not_registered
  defp reg_status(1), do: :registered_home
  defp reg_status(2), do: :searching
  defp reg_status(3), do: :denied
  defp reg_status(4), do: :unknown
  defp reg_status(5), do: :registered_roaming
  defp reg_status(_), do: :unknown

  defp access_tech(0), do: :gsm
  defp access_tech(2), do: :utran
  defp access_tech(3), do: :gsm_egprs
  defp access_tech(4), do: :utran_hsdpa
  defp access_tech(5), do: :utran_hsupa
  defp access_tech(6), do: :utran_hsdpa_hsupa
  defp access_tech(7), do: :lte
  defp access_tech(8), do: :cat_m1
  defp access_tech(9), do: :nb_iot
  defp access_tech(_), do: :unknown

  defp act_from_list([act | _]), do: access_tech(to_int(act))
  defp act_from_list([]), do: nil

  defp interface_ip(name) do
    charlist = String.to_charlist(name)

    case :inet.getifaddrs() do
      {:ok, ifaddrs} ->
        case List.keyfind(ifaddrs, charlist, 0) do
          {_, opts} ->
            case Keyword.get(opts, :addr) do
              nil -> {:error, {:no_address, name}}
              addr -> {:ok, addr}
            end

          nil ->
            {:error, {:interface_not_found, name}}
        end

      error ->
        error
    end
  end

  defp tcp_reachable?(host, port, sock_opts, timeout) do
    case :gen_tcp.connect(host, port, [:binary, active: false] ++ sock_opts, timeout) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      _ ->
        false
    end
  end

  defp split_csv(str), do: str |> String.split(",") |> Enum.map(&String.trim/1)

  defp to_int(s) when is_binary(s) do
    case Integer.parse(String.trim(s)) do
      {n, _} -> n
      :error -> s
    end
  end

  defp to_int(n), do: n

  defp unquote_str(s), do: s |> String.trim() |> String.trim("\"")
end
