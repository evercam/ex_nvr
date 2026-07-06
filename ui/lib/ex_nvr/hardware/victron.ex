defmodule ExNVR.Hardware.Victron do
  @moduledoc """
  Data structure and pure parsing logic for Victron Energy products.

  The data are retrieved via a serial port using the VE.Direct protocol. This
  module holds no state: it only defines the `t:t/0` struct and the pure
  functions used to parse the text/hex frames exchanged with the device. The
  stateful part (opening the serial port, buffering incoming bytes, replying to
  in-flight requests) lives in `ExNVR.Hardware.Victron.Server`.

  For now we support getting data for MPPT and SmartShunt, however the module
  can be extended to get information from other products such as:

    * BMV 60x
    * BMV 70x
    * Phoenix Inverter
    * Phoenix Charger
    * Smart BuckBoost
  """

  import Bitwise

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

  @type load_output_state :: :off | :auto | :alt1 | :alt2 | :on | :user1 | :user2 | :aes

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

  @battery_monitor_pids ["0xA389", "0xA38A", "0xA38B"]

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

  @load_output_state %{
    off: 0,
    auto: 1,
    alt1: 2,
    alt2: 3,
    on: 4,
    user1: 5,
    user2: 6,
    aes: 7
  }

  @doc """
  Whether the given product id belongs to a battery monitor (SmartShunt).

  Any other product id is treated as a solar charger (MPPT).
  """
  @spec battery_monitor?(binary() | nil) :: boolean()
  def battery_monitor?(pid), do: pid in @battery_monitor_pids

  @doc """
  The hex command used to query the current load output state.
  """
  @spec load_output_state_query() :: binary()
  def load_output_state_query, do: ":7ABED00B6\n"

  @doc """
  Build the hex command that sets the load output to `new_state`.
  """
  @spec set_load_output_state_command(load_output_state()) :: binary()
  def set_load_output_state_command(new_state) do
    value = @load_output_state[new_state]
    checksum = 0xB5 - value

    value = value |> Integer.to_string(16) |> String.pad_leading(2, "0") |> String.upcase()
    checksum = checksum |> Integer.to_string(16) |> String.pad_leading(2, "0") |> String.upcase()

    String.upcase(":8ABED00#{value}#{checksum}\n")
  end

  @doc """
  Parse a hex response to a (get/set) load output state request.

  Returns:

    * `:ignore` - the message is an asynchronous message and should be discarded.
    * `{:ok, state}` - the load output `state` reported by the device.
    * `{:error, reason}` - the response was invalid or unexpected.
  """
  @spec parse_load_output_response(binary()) ::
          :ignore | {:ok, load_output_state()} | {:error, term()}
  def parse_load_output_response(<<"A", _rest::binary>>), do: :ignore

  def parse_load_output_response(
        <<_::8, "ABED", flags::binary-size(2), value::binary-size(2), _checksum::binary-size(2)>>
      ) do
    if String.to_integer(flags, 16) == 0 do
      look = String.to_integer(value, 16)

      {:ok, Enum.find_value(@load_output_state, fn {key, value} -> if value == look, do: key end)}
    else
      {:error, :invalid_response}
    end
  end

  def parse_load_output_response(_message), do: {:error, :unexpected_response}

  @doc """
  Parse the `buffer` received from the device, updating `data` accordingly.

  Text frames (`key\\tvalue`) update the `data` struct while hex frames are
  collected and returned so the caller can match them to in-flight requests.

  Returns `{updated_data, hex_messages, remaining_buffer}` where:

    * `updated_data` - the `data` struct updated with every complete text frame.
    * `hex_messages` - the complete hex frames encountered, in order.
    * `remaining_buffer` - the trailing incomplete frame, to be prepended to the
      next chunk of data.
  """
  @spec parse(t(), binary()) :: {t(), [binary()], binary()}
  def parse(%__MODULE__{} = data, buffer) do
    {data, hex, rest} = do_parse(data, [], :text, buffer)
    {data, Enum.reverse(hex), rest}
  end

  defp do_parse(data, hex, :hex, message) do
    case String.split(message, "\n", parts: 2) do
      [message, rest] ->
        {mode, rest} =
          if String.starts_with?(rest, ":"),
            do: {:hex, binary_part(rest, 1, byte_size(rest) - 1)},
            else: {:text, rest}

        do_parse(data, [message | hex], mode, rest)

      [incomplete] ->
        {data, hex, incomplete}
    end
  end

  defp do_parse(data, hex, :text, message) do
    case String.split(message, "\r\n", parts: 2) do
      [line, rest] ->
        # check if there's any hex message
        {line, hex_frame} =
          case String.split(line, ":", parts: 2) do
            [line, hex_frame] -> {line, hex_frame}
            _ -> {line, nil}
          end

        data =
          case String.split(line, "\t") do
            [key, value] -> do_handle_value(data, String.downcase(key), value)
            _other -> data
          end

        if hex_frame,
          do: do_parse(data, hex, :hex, hex_frame <> rest),
          else: do_parse(data, hex, :text, rest)

      [incomplete] ->
        {data, hex, incomplete}
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

  defp do_handle_value(data, "relay", value) do
    %{data | relay_state: value |> String.downcase() |> String.to_existing_atom()}
  end

  defp do_handle_value(data, key, value) when key in ["alarm", "load"] do
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
      case band(value, 1) do
        0 -> {alarms, bsr(value, 1)}
        1 -> {[alarm | alarms], bsr(value, 1)}
      end
    end)
    |> elem(0)
  end
end
