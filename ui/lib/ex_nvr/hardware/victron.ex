defmodule ExNVR.Hardware.Victron do
  @moduledoc """
  Module responsible for getting data from Victron Energy products.

  The data are retrieved via a serial port.

  For now we support getting data for MPPT and SmartShunt, however the module
  can be extended to get information from other products such as:

    * BMV 60x
    * BMV 70x
    * Phoenix Inverter
    * Phoenix Charger
    * Smart BuckBoost
  """
  require Logger

  use GenServer, restart: :transient

  @type operation_state ::
          :off
          | :fault
          | :bulk
          | :absorption
          | :float
          | :equalize
          | :starting_up
          | :auto_equalize
          | :external_control
          | :unknown

  @typedoc """
  A struct describing the date retrieved from the MPPT.

    * `v` - Main or channel 1 (battery) voltage in mV.
    * `vpv` - Panel voltage in mV
    * `ppv` - Panel power in watts (W).
    * `i` - Main or channel 1 battery current in mA.
    * `il` - Load current in mA.
    * `p` - Instantaneous power.
    * `battery_temp` - Battery temperature.
    * `consumed_amps` - Comsumed amp hours in mAh.
    * `soc` - State of charge ‰.
    * `ttg` - Time to go for the battery in minutes.
    * `load` - Load output state.
    * `relay_state` - The relay state.
    * `off_reason` - The off reason.
    * `alarm` - Alarm state (ON/OFF).
    * `alarm_reasons` - The alarm reasons if `alarm` is on.
    * `h1` - Depth of the deepest discharge in mAh.
    * `h2` - Depth of the last discharge in mAh.
    * `h3` - Depth of the average discharge in mAh.
    * `h4` - Number of charge cycles.
    * `h5` - Number of full discharges.
    * `h6` - Cumulative Amps hours drawn in mAh.
    * `h9` - Number of seconds since last full charge.
    * `h19` - Yield total in 0.01 kWh.
    * `h20` - Yield today in 0.01 kWh.
    * `h21` - Maximum power today in W.
    * `h22` - Yield yesterday in 0.01 kWh.
    * `h23` - Maximum power yesterday in W.
    * `err` - Error code.
    * `cs` - State of operation.
    * `fw` - Firmware version
    * `pid` - Product id.
    * `serial_number` - Serial number.
  """
  @type t :: %__MODULE__{
          v: integer(),
          vpv: integer(),
          ppv: integer(),
          i: integer(),
          il: integer(),
          battery_temp: integer(),
          p: integer(),
          consumed_amps: integer(),
          soc: integer(),
          ttg: integer(),
          load: :on | :off,
          relay_state: :on | :off,
          off_reason: integer(),
          alarm: :on | :off,
          alarm_reasons: [atom()],
          h1: integer(),
          h2: integer(),
          h3: integer(),
          h4: integer(),
          h5: integer(),
          h6: integer(),
          h9: integer(),
          h19: integer(),
          h20: integer(),
          h21: integer(),
          h22: integer(),
          h23: integer(),
          err: integer(),
          cs: operation_state(),
          fw: binary(),
          pid: binary(),
          serial_number: binary()
        }

  @derive Jason.Encoder
  # credo:disable-for-next-line
  defstruct [
    :v,
    :vpv,
    :ppv,
    :i,
    :il,
    :battery_temp,
    :p,
    :consumed_amps,
    :soc,
    :ttg,
    :load,
    :relay_state,
    :off_reason,
    :alarm,
    :alarm_reasons,
    :err,
    :cs,
    :fw,
    :pid,
    :serial_number,
    h1: 0,
    h2: 0,
    h3: 0,
    h4: 0,
    h5: 0,
    h6: 0,
    h9: 0,
    h19: 0,
    h20: 0,
    h21: 0,
    h22: 0,
    h23: 0
  ]

  @speed 19_200
  @reporting_interval :timer.seconds(15)
  @restart_interval :timer.hours(1)
  @last_data_update_in_seconds 30

  @alarm_reasons [
    :low_voltage,
    :high_voltage,
    :low_soc,
    :low_starter_voltage,
    :high_starter_voltage,
    :low_temp,
    :high_temp,
    :mid_voltage
  ]

  def start_link(options) do
    GenServer.start_link(__MODULE__, options[:port], name: options[:name])
  end

  @impl true
  def init(serial_port) do
    {:ok, pid} = Circuits.UART.start_link()

    state = %{
      serial_port: serial_port,
      pid: pid,
      data: %__MODULE__{},
      timer: nil,
      restart_timer: nil,
      datetime: DateTime.utc_now()
    }

    {:ok, state, {:continue, :probe}}
  end

  @impl true
  def handle_continue(:probe, state) do
    with :ok <- Circuits.UART.open(state.pid, state.serial_port, uart_options()),
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
  end

  @impl true
  def handle_info({:circuits_uart, _port, message}, state) do
    state = %{state | data: do_handle_message(state.data, message), datetime: DateTime.utc_now()}
    {:noreply, state}
  end

  @impl true
  def handle_info(:report, state) do
    time_diff = DateTime.diff(DateTime.utc_now(), state.datetime)

    data =
      if is_nil(state.data.v) or time_diff >= @last_data_update_in_seconds,
        do: nil,
        else: state.data

    # check if it's a smart shunt
    if state.data.pid in ["0xA389", "0xA38A", "0xA38B"],
      do: ExNVR.SystemStatus.set(:battery_monitor, data),
      else: ExNVR.SystemStatus.set(:solar_charger, data)

    {:noreply, state}
  end

  @impl true
  def handle_info(:restart, state) do
    # Sometimes the Victron stuck and send the same
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

      if pid in ["0xA389", "0xA38A", "0xA38B"],
        do: ExNVR.SystemStatus.set(:battery_monitor, nil),
        else: ExNVR.SystemStatus.set(:solar_charger, nil)
    end

    Circuits.UART.close(state.pid)
    Circuits.UART.stop(state.pid)
    :timer.cancel(state.timer)
  end

  defp uart_options(active \\ false) do
    [
      active: active,
      speed: @speed,
      framing: {Circuits.UART.Framing.Line, separator: "\r\n"}
    ]
  end

  defp victron_device?(state, max_attemots \\ 3)

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

  defp do_handle_message(%__MODULE__{} = data, message) do
    case String.split(message, "\t") do
      [key, value] -> do_handle_value(data, String.downcase(key), value)
      _other -> data
    end
  end

  defp do_handle_value(data, "pid", value), do: %{data | pid: value}
  defp do_handle_value(data, "fw", value), do: %{data | fw: value}
  defp do_handle_value(data, "ser#", value), do: %{data | serial_number: value}
  defp do_handle_value(data, "v", value), do: %{data | v: String.to_integer(value)}
  defp do_handle_value(data, "i", value), do: %{data | i: String.to_integer(value)}
  defp do_handle_value(data, "vpv", value), do: %{data | vpv: String.to_integer(value)}
  defp do_handle_value(data, "ppv", value), do: %{data | ppv: String.to_integer(value)}
  defp do_handle_value(data, "il", value), do: %{data | il: String.to_integer(value)}
  defp do_handle_value(data, "t", value), do: %{data | battery_temp: String.to_integer(value)}
  defp do_handle_value(data, "p", value), do: %{data | p: String.to_integer(value)}
  defp do_handle_value(data, "ce", value), do: %{data | consumed_amps: String.to_integer(value)}
  defp do_handle_value(data, "soc", value), do: %{data | soc: String.to_integer(value)}
  defp do_handle_value(data, "ttg", value), do: %{data | ttg: String.to_integer(value)}
  defp do_handle_value(data, "h1", value), do: %{data | h1: String.to_integer(value)}
  defp do_handle_value(data, "h2", value), do: %{data | h2: String.to_integer(value)}
  defp do_handle_value(data, "h3", value), do: %{data | h3: String.to_integer(value)}
  defp do_handle_value(data, "h4", value), do: %{data | h4: String.to_integer(value)}
  defp do_handle_value(data, "h5", value), do: %{data | h5: String.to_integer(value)}
  defp do_handle_value(data, "h6", value), do: %{data | h6: String.to_integer(value)}
  defp do_handle_value(data, "h9", value), do: %{data | h9: String.to_integer(value)}
  defp do_handle_value(data, "h19", value), do: %{data | h19: String.to_integer(value)}
  defp do_handle_value(data, "h20", value), do: %{data | h20: String.to_integer(value)}
  defp do_handle_value(data, "h21", value), do: %{data | h21: String.to_integer(value)}
  defp do_handle_value(data, "h22", value), do: %{data | h22: String.to_integer(value)}
  defp do_handle_value(data, "h23", value), do: %{data | h23: String.to_integer(value)}
  defp do_handle_value(data, "or", value), do: %{data | off_reason: from_hex(value)}
  defp do_handle_value(data, "err", value), do: %{data | err: String.to_integer(value)}

  defp do_handle_value(data, "cs", value),
    do: %{data | cs: String.to_integer(value) |> operation_state()}

  defp do_handle_value(data, key, value) when key in ["relay", "alarm", "load"] do
    Map.put(data, String.to_atom(key), String.downcase(value) |> String.to_existing_atom())
  end

  defp do_handle_value(data, "ar", value), do: %{data | alarm_reasons: alarm_reasons(value)}

  defp do_handle_value(data, _key, _value), do: data

  defp from_hex("0x" <> hex), do: String.to_integer(hex, 16)
  defp from_hex(hex), do: String.to_integer(hex, 16)

  defp operation_state(0), do: :off
  defp operation_state(2), do: :fault
  defp operation_state(3), do: :bulk
  defp operation_state(4), do: :absorption
  defp operation_state(5), do: :float
  defp operation_state(7), do: :equalize
  defp operation_state(245), do: :starting_up
  defp operation_state(247), do: :auto_equalize
  defp operation_state(252), do: :external_control
  defp operation_state(_other), do: :unknown

  defp alarm_reasons(value) do
    value = String.to_integer(value)

    @alarm_reasons
    |> Enum.reduce({[], value}, fn alarm, {alarms, value} ->
      case Bitwise.band(value, 1) do
        0 -> {alarms, Bitwise.bsr(value, 1)}
        1 -> {[alarm | alarms], Bitwise.bsr(value, 1)}
      end
    end)
    |> elem(0)
  end
end
