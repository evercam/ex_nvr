defmodule ExNVR.Hardware.Victron.Server do
  @moduledoc """
  GenServer responsible for getting data from Victron Energy products.

  It owns the serial port connection and all mutable state (incoming byte
  buffer, in-flight requests, timers). The actual parsing of the VE.Direct
  frames is delegated to the stateless `ExNVR.Hardware.Victron` module.
  """

  use GenServer, restart: :transient

  require Logger

  alias ExNVR.Hardware.Victron

  @speed 19_200
  @reporting_interval :timer.seconds(15)
  @restart_interval :timer.hours(1)
  @last_data_update_in_seconds 30

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    GenServer.start_link(__MODULE__, options[:port], name: options[:name])
  end

  @spec write(GenServer.name(), binary()) :: :ok
  def write(pid, data) do
    GenServer.call(pid, {:write, data})
  end

  @spec load_output_state(GenServer.name()) ::
          {:ok, Victron.load_output_state()} | {:error, term()}
  def load_output_state(pid) do
    GenServer.call(pid, :load_output_state)
  end

  @spec set_load_output_state(GenServer.name(), Victron.load_output_state()) ::
          {:ok, Victron.load_output_state()} | {:error, term()}
  def set_load_output_state(pid, new_state) do
    GenServer.call(pid, {:load_output_state, new_state})
  end

  @impl true
  def init(serial_port) do
    {:ok, pid} = Circuits.UART.start_link()

    state = %{
      serial_port: serial_port,
      pid: pid,
      data: %Victron{},
      connected: false,
      timer: nil,
      restart_timer: nil,
      datetime: DateTime.utc_now(),
      unprocessed_data: <<>>,
      inflight_requests: []
    }

    {:ok, state, {:continue, :probe}}
  end

  @impl true
  def handle_continue(:probe, state) do
    with :ok <- Circuits.UART.open(state.pid, state.serial_port, uart_options()),
         state <- %{state | connected: true},
         true <- victron_device?(state) do
      Circuits.UART.configure(state.pid, active: true)
      {:ok, timer_ref} = :timer.send_interval(@reporting_interval, :report)
      {:ok, restart_timer} = :timer.send_interval(@restart_interval, :restart)
      {:noreply, %{state | timer: timer_ref, restart_timer: restart_timer}}
    else
      _other ->
        Logger.info("#{inspect(state.serial_port)} is not a victron serial port")
        {:stop, :normal, state}
    end
  catch
    :exit, _error -> {:stop, :normal, state}
  end

  @impl true
  def handle_call({:write, data}, _from, state) do
    :ok = Circuits.UART.write(state.pid, data)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:load_output_state, from, state) do
    :ok = Circuits.UART.write(state.pid, Victron.load_output_state_query())

    {:noreply,
     %{state | inflight_requests: state.inflight_requests ++ [{:load_output_state, from}]}}
  end

  @impl true
  def handle_call({:load_output_state, new_state}, from, state) do
    :ok = Circuits.UART.write(state.pid, Victron.set_load_output_state_command(new_state))

    {:noreply,
     %{state | inflight_requests: state.inflight_requests ++ [{:load_output_state, from}]}}
  end

  @impl true
  def handle_info({:circuits_uart, _port, message}, state) do
    {data, hex_messages, unprocessed_data} =
      Victron.parse(state.data, state.unprocessed_data <> message)

    state = %{state | data: data, unprocessed_data: unprocessed_data}
    state = reply_to_hex_messages(state, hex_messages)
    state = %{state | datetime: DateTime.utc_now()}
    {:noreply, state}
  end

  @impl true
  def handle_info(:report, state) do
    time_diff = DateTime.diff(DateTime.utc_now(), state.datetime)

    data =
      if is_nil(state.data.v) or time_diff >= @last_data_update_in_seconds,
        do: nil,
        else: state.data

    if Victron.battery_monitor?(state.data.pid),
      do: ExNVR.SystemStatus.set(:battery_monitor, data),
      else: ExNVR.SystemStatus.set(:solar_charger, data)

    {:noreply, state}
  end

  @impl true
  def handle_info(:restart, state) do
    # Sometimes the Victron stuck and send the same data
    # we restart the connection to avoid such issues
    :ok = Circuits.UART.close(state.pid)
    :ok = Circuits.UART.open(state.pid, state.serial_port, uart_options(true))

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    if pid = state.data.pid do
      Logger.warning("Victron process terminating due to #{inspect(reason)}")

      if Victron.battery_monitor?(pid),
        do: ExNVR.SystemStatus.set(:battery_monitor, nil),
        else: ExNVR.SystemStatus.set(:solar_charger, nil)
    end

    if state.connected do
      Circuits.UART.close(state.pid)
    end

    Circuits.UART.stop(state.pid)
    :timer.cancel(state.timer)
  end

  # replies to in-flight requests as their hex responses come in, in order
  defp reply_to_hex_messages(state, []), do: state

  defp reply_to_hex_messages(state, [message | rest]) do
    state =
      case Victron.parse_load_output_response(message) do
        :ignore ->
          Logger.debug("[Victron] hex: ignore asynchronous message")
          state

        reply ->
          case state.inflight_requests do
            [{_op, requester} | remaining] ->
              GenServer.reply(requester, reply)
              %{state | inflight_requests: remaining}

            [] ->
              Logger.debug("Victron hex message received: #{inspect(message, limit: :infinity)}")
              state
          end
      end

    reply_to_hex_messages(state, rest)
  end

  defp uart_options(active \\ false), do: [active: active, speed: @speed]

  defp victron_device?(state, max_attempts \\ 3)

  defp victron_device?(_state, 0), do: false

  # for now we do a simple test to check if the device is a victron device
  # data should be in the format of "key\tvalue"
  defp victron_device?(state, max_attempts) do
    with {:ok, data} when is_binary(data) <- Circuits.UART.read(state.pid, 1000),
         [_key, _value] <- String.split(data, "\t") do
      true
    else
      _other -> victron_device?(state, max_attempts - 1)
    end
  end
end
