defmodule ExNVR.RTSP.Source.StreamHandler do
  @moduledoc """
  Handle an RTP stream.
  """

  require Logger

  alias Membrane.{Buffer, Time}

  @timestamp_limit Bitwise.bsl(1, 32)
  @seq_number_limit Bitwise.bsl(1, 16)

  @type t :: %__MODULE__{
          timestamps: {integer(), integer()} | nil,
          clock_rate: pos_integer(),
          parser_mod: module(),
          parser_state: any(),
          buffered_actions: [],
          previous_seq_num: integer() | nil
        }

  defstruct [
    :parser_mod,
    :parser_state,
    timestamps: nil,
    clock_rate: 90_000,
    buffered_actions: [],
    previous_seq_num: nil
  ]

  @spec handle_packet(t(), ExRTP.Packet.t()) :: {[Buffer.t()], t()}
  def handle_packet(handler, packet) do
    {event, handler} =
      if discontinuty?(packet, handler.previous_seq_num) do
        {%Membrane.Event.Discontinuity{}, reset_state(handler)}
      else
        {[], handler}
      end

    {buffers, handler} =
      %{handler | previous_seq_num: packet.sequence_number}
      |> convert_timestamp(packet)
      |> parse()

    {event ++ buffers, handler}
  end

  @spec discontinuty?(ExRTP.Packet.t(), integer() | nil) :: boolean()
  defp discontinuty?(_rtp_packet, nil), do: false

  defp discontinuty?(%{sequence_number: seq_num}, previous_seq_num) do
    rem(previous_seq_num + 1, @seq_number_limit) != seq_num
  end

  @spec convert_timestamp(t(), ExRTP.Packet.t()) :: {t(), ExRTP.Packet.t()}
  defp convert_timestamp(handler, %{timestamp: rtp_timestamp} = packet) do
    {timestamp_base, previous_timestamp} = handler.timestamps || {rtp_timestamp, rtp_timestamp}

    # timestamps in RTP don't have to be monotonic therefore there can be
    # a situation where in 2 consecutive packets the latter packet will have smaller timestamp
    # than the previous one while not overflowing the timestamp number
    # https://datatracker.ietf.org/doc/html/rfc3550#section-5.1

    timestamp_base =
      case from_which_rollover(previous_timestamp, rtp_timestamp, @timestamp_limit) do
        :next -> timestamp_base - @timestamp_limit
        :previous -> timestamp_base + @timestamp_limit
        :current -> timestamp_base
      end

    timestamp = div((rtp_timestamp - timestamp_base) * Time.second(), handler.clock_rate)
    {%{handler | timestamps: {timestamp_base, rtp_timestamp}}, %{packet | timestamp: timestamp}}
  end

  defp parse({handler, packet}) do
    case handler.parser_mod.handle_packet(packet, handler.parser_state) do
      {:ok, {buffers, state}} ->
        {buffers, %{handler | parser_state: state}}

      {:error, reason, state} ->
        Logger.warning("""
        Could not depayload rtp packet, ignoring...
        Error reason: #{inspect(reason)}
        Packet: #{inspect(packet, limit: :infinity)}
        """)

        {[], %{handler | parser_state: state}}
    end
  end

  defp reset_state(handler) do
    %{handler | depayloader_state: handler.depayloader_mod.init()}
  end

  @spec from_which_rollover(number(), number(), number()) :: :current | :previous | :next
  def from_which_rollover(previous_value, new_value, rollover_length) do
    # a) current rollover
    distance_if_current = abs(previous_value - new_value)
    # b) new_value is from the previous rollover
    distance_if_previous = abs(previous_value - (new_value - rollover_length))
    # c) new_value is in the next rollover
    distance_if_next = abs(previous_value - (new_value + rollover_length))

    [
      {:current, distance_if_current},
      {:previous, distance_if_previous},
      {:next, distance_if_next}
    ]
    |> Enum.min_by(fn {_atom, distance} -> distance end)
    |> then(fn {result, _value} -> result end)
  end
end
