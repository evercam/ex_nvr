defmodule ExNVR.Hardware.SolarCharger.VictronMPPT do
  @moduledoc """
  Module responsible for monitoring Victron MPPT.

  The data are retrieved via a serial port using a VE.DIRECT to USB.

  For now we support getting information for only MPPT, however the module
  can be extended to get information from other products such as:

    * BMV 60x
    * BMV 70x
    * BMV71x SmartShunt
    * Phoenix Inverter
    * Phoenix Charger
    * Smart BuckBoost
  """

  use GenServer

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
    * `load` - Load output state.
    * `relay_state` - The relay state.
    * `off_reason` - The off reason.
    * `h19` - Yield total in 0.01 kWh.
    * `h20` - Yield today in 0.01 kWh.
    * `h21` - Maximum power today in W.
    * `h22` - Yield yesterday in 0.01 kWh.
    * `h23` - Maximum power yesterday in W.
    * `err` - Error code.
    * `cs` - State of operation.
    * `fw` - Firmware version
    * `pid` - Poduct id.
    * `serial_number` - Serial number.
  """
  @type t :: %__MODULE__{
          v: integer(),
          vpv: integer(),
          ppv: integer(),
          i: integer(),
          il: integer(),
          load: :on | :off,
          relay_state: :on | :off,
          off_reason: integer(),
          h19: integer() | nil,
          h20: integer() | nil,
          h21: integer() | nil,
          h22: integer() | nil,
          h23: integer() | nil,
          err: integer(),
          cs: operation_state(),
          fw: binary(),
          pid: binary(),
          serial_number: binary()
        }

  @derive Jason.Encoder
  defstruct [
    :v,
    :vpv,
    :ppv,
    :i,
    :il,
    :load,
    :relay_state,
    :off_reason,
    :err,
    :cs,
    :fw,
    :pid,
    :serial_number,
    h19: 0,
    h20: 0,
    h21: 0,
    h22: 0,
    h23: 0
  ]

  @speed 19_200
  @reporting_interval :timer.seconds(15)
  @last_data_update_in_seconds 30

  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  @impl true
  def init(options) do
    {:ok, pid} = Circuits.UART.start_link()

    :ok =
      Circuits.UART.open(pid, options[:port],
        speed: @speed,
        active: true,
        framing: {Circuits.UART.Framing.Line, separator: "\r\n"}
      )

    {:ok, timer_ref} = :timer.send_interval(@reporting_interval, :report)

    ExNVR.SystemStatus.register(:solar_charger)

    {:ok,
     %{
       pid: pid,
       data: %__MODULE__{},
       timer: timer_ref,
       datetime: DateTime.utc_now()
     }}
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

    :telemetry.execute([:system, :status, :solar_charger], %{value: data})

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Circuits.UART.close(state.pid)
    :timer.cancel(state.timer)
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
  defp do_handle_value(data, "h19", value), do: %{data | h19: String.to_integer(value)}
  defp do_handle_value(data, "h20", value), do: %{data | h20: String.to_integer(value)}
  defp do_handle_value(data, "h21", value), do: %{data | h21: String.to_integer(value)}
  defp do_handle_value(data, "h22", value), do: %{data | h22: String.to_integer(value)}
  defp do_handle_value(data, "h23", value), do: %{data | h23: String.to_integer(value)}
  defp do_handle_value(data, "or", value), do: %{data | off_reason: from_hex(value)}
  defp do_handle_value(data, "err", value), do: %{data | err: String.to_integer(value)}

  defp do_handle_value(data, "load", value),
    do: %{data | load: String.downcase(value) |> String.to_existing_atom()}

  defp do_handle_value(data, "cs", value),
    do: %{data | cs: String.to_integer(value) |> operation_state()}

  defp do_handle_value(data, "relay", value),
    do: %{data | relay: String.downcase(value) |> String.to_existing_atom()}

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
end
