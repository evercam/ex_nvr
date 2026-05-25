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
  @reconnect_interval 5_000

  @final_codes ~w(OK ERROR CONNECT NO\ CARRIER BUSY NO\ ANSWER NO\ DIALTONE)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start(opts \\ []) do
    GenServer.start(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Send a raw AT command and return `{:ok, response}` or `{:error, reason}`."
  def send_command(command, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(__MODULE__, {:send_command, command}, timeout + 1_000)
  end

  @doc "Close the UART connection."
  def close, do: GenServer.call(__MODULE__, :close)

  @doc "Close and reopen the UART connection."
  def reconnect, do: GenServer.call(__MODULE__, :reconnect)

  # Basic

  @doc "AT — ping the modem."
  def ping, do: send_command("AT")

  @doc "ATI — device identification."
  def identify, do: send_command("ATI")

  @doc "AT+CGMI — manufacturer name."
  def manufacturer, do: send_command("AT+CGMI")

  @doc "AT+CGMM — model name."
  def model, do: send_command("AT+CGMM")

  @doc "AT+CGMR — firmware revision."
  def firmware_version, do: send_command("AT+CGMR")

  @doc "AT+CGSN — IMEI."
  def imei, do: send_command("AT+CGSN")

  @doc "AT+CIMI — IMSI."
  def imsi, do: send_command("AT+CIMI")

  @doc "AT+ICCID — SIM ICCID."
  def iccid, do: send_command("AT+ICCID")

  # SIM / network status

  @doc "AT+CPIN? — SIM PIN status."
  def sim_status, do: send_command("AT+CPIN?")

  @doc "AT+CSQ — signal quality (RSSI + BER)."
  def signal_quality, do: send_command("AT+CSQ")

  @doc "AT+CREG? — GSM/GPRS network registration."
  def network_registration, do: send_command("AT+CREG?")

  @doc "AT+CEREG? — LTE network registration."
  def eps_registration, do: send_command("AT+CEREG?")

  @doc "AT+COPS? — current operator."
  def operator, do: send_command("AT+COPS?")

  @doc "AT+COPS=? — list available operators (long running)."
  def scan_operators, do: send_command("AT+COPS=?", timeout: 60_000)

  # PDP / data

  @doc "AT+CGDCONT? — list PDP contexts."
  def pdp_contexts, do: send_command("AT+CGDCONT?")

  @doc "AT+CGDCONT — define a PDP context."
  def set_pdp_context(cid, type \\ "IP", apn),
    do: send_command("AT+CGDCONT=#{cid},\"#{type}\",\"#{apn}\"")

  @doc "AT+CGACT? — PDP context activation states."
  def context_states, do: send_command("AT+CGACT?")

  @doc "AT+CGACT=1 — activate a PDP context."
  def activate_context(cid), do: send_command("AT+CGACT=1,#{cid}")

  @doc "AT+CGACT=0 — deactivate a PDP context."
  def deactivate_context(cid), do: send_command("AT+CGACT=0,#{cid}")

  # SMS

  @doc "AT+CMGF — set SMS message format (0=PDU, 1=text)."
  def set_sms_format(n \\ 1), do: send_command("AT+CMGF=#{n}")

  @doc "AT+CMGL — list SMS messages."
  def list_sms(stat \\ "ALL"), do: send_command("AT+CMGL=\"#{stat}\"", timeout: 15_000)

  @doc "AT+CMGR — read a single SMS by index."
  def read_sms(index), do: send_command("AT+CMGR=#{index}")

  @doc "AT+CMGD — delete SMS by index."
  def delete_sms(index), do: send_command("AT+CMGD=#{index}")

  # Control

  @doc "AT+CMEE — enable extended error reporting (2=verbose)."
  def set_error_format(n \\ 2), do: send_command("AT+CMEE=#{n}")

  @doc "AT+CFUN — set phone functionality (0=min, 1=full, 4=airplane)."
  def set_functionality(fun \\ 1), do: send_command("AT+CFUN=#{fun}")

  @doc "AT+CFUN? — get current phone functionality."
  def functionality, do: send_command("AT+CFUN?")

  @doc "AT+CFUN=1,1 — reboot the modem. The modem may not send OK before resetting."
  def reboot, do: send_command("AT+CFUN=1,1")

  @doc "AT&F — restore factory defaults."
  def factory_reset, do: send_command("AT&F")

  @doc "ATZ — soft reset."
  def reset, do: send_command("ATZ")

  @doc "AT+CGPADDR — IP address(es) assigned to PDP context(s)."
  def pdp_address(cid \\ 1), do: send_command("AT+CGPADDR=#{cid}")

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
      # {from, cancel_timer_ref, [accumulated_lines]}
      pending: nil,
      queue: :queue.new()
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case UART.open(state.uart, state.device,
           speed: state.speed,
           active: true,
           framing: {UART.Framing.Line, separator: "\r\n"}
         ) do
      :ok ->
        Logger.info("ATModem: connected to #{state.device}")
        {:noreply, state}

      {:error, reason} ->
        Logger.error("ATModem: failed to open #{state.device}: #{inspect(reason)}")
        Process.send_after(self(), :reconnect, @reconnect_interval)
        {:noreply, state}
    end
  end

  @impl true
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

    case UART.open(state.uart, state.device,
           speed: state.speed,
           active: true,
           framing: {UART.Framing.Line, separator: "\r\n"}
         ) do
      :ok ->
        Logger.info("ATModem: reconnected to #{state.device}")
        {:reply, :ok, state}

      {:error, reason} = error ->
        Logger.error("ATModem: reconnect failed: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_info({:circuits_uart, _port, data}, state) do
    {:noreply, process_line(state, String.trim(data))}
  end

  def handle_info(:command_timeout, %{pending: {:cmd, from, _timer, _lines}} = state) do
    Logger.warning("ATModem: command timed out")
    GenServer.reply(from, {:error, :timeout})
    {:noreply, maybe_dispatch(%{state | pending: nil})}
  end

  def handle_info(:command_timeout, state), do: {:noreply, state}

  def handle_info(:reconnect, state), do: handle_continue(:connect, state)

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

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
