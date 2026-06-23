defmodule ExNVR.Nerves.Modem.Sms do
  @moduledoc """
    configurations to a modem via AT commands
    recieving and sending sms
  """
  use GenServer

  @port "ttyUSB2"
  @baud 115_200

  ## Public API

  def start_link(_state \\ %{}) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def echo_modem do
    GenServer.call(__MODULE__, :echo)
  end

  def send_message(message, send_to) do
    GenServer.cast(__MODULE__, {:send_sms, message, send_to})
  end

  ## GenServer callbacks

  @impl true
  def init(state) do
    {:ok, pid} = Circuits.UART.start_link()

    :ok =
      Circuits.UART.open(pid, @port,
        speed: @baud,
        active: true
      )

    set_modem_to_receive_mode(pid)

    {:ok, Map.put(state, :pid, pid)}
  end

  @impl true
  def handle_info({:circuits_uart, _port, data}, state) do
    cond do
      String.contains?(data, "+CMTI") ->
        handle_cmti(data, state)

      String.contains?(data, "+CMGR") ->
        handle_cmgr(data, state)

      true ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:echo, _from, state) do
    Circuits.UART.write(state.pid, "AT\r\n")
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:send_sms, message, send_to}, state) do
    write(state.pid, "AT+CMGF=1")
    write(state.pid, "AT+CMGS=\"#{send_to}\"")
    Circuits.UART.write(state.pid, message <> <<26>>)
    {:noreply, state}
  end

  ## Internal helpers

  defp write(pid, cmd) do
    Circuits.UART.write(pid, cmd <> "\r\n")
    Process.sleep(200)
  end

  defp set_modem_to_receive_mode(pid) do
    write(pid, "AT")
    write(pid, "AT+CMGF=1")
    write(pid, "AT+CPMS=\"SM\",\"SM\",\"SM\"")
    write(pid, "AT+CNMI=2,1,0,0,0")
    write(pid, "AT+CMGR=3")
    write(pid, "AT+CMGR=2")
    write(pid, "AT+CMGR=1")
    write(pid, "AT+CMGR=0")
  end

  defp handle_cmti(data, state) do
    case Regex.run(~r/\+CMTI:\s*"SM",(\d+)/, data) do
      [_, index] ->
        Circuits.UART.write(state.pid, "AT+CMGR=#{index}\r\n")
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  defp handle_cmgr(data, state) do
    case extract_message(data) do
      {:ok, sms} ->
        Phoenix.PubSub.broadcast(ExNVR.Nerves.PubSub, "messages", {:modem_messages, sms})

        {:noreply, Map.put(state, :last_sms, sms)}

      _ ->
        {:noreply, state}
    end
  end

  defp extract_message(data) do
    regex =
      ~r/\+CMGR:\s+"(?<status>[^"]+)",\s*"(?<sender>[^"]+)",.*?"(?<timestamp>[^"]+)"\r\n(?<message>.*?)\r\n/s

    case Regex.named_captures(regex, data) do
      nil -> {:error, :no_match}
      captures -> {:ok, captures}
    end
  end
end
