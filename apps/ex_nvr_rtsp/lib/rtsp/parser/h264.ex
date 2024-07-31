defmodule ExNVR.RTSP.Parser.H264 do
  @moduledoc """
  Parse H264 NAL units
  """

  @behaviour ExNVR.RTSP.Parser

  require Logger

  alias ExNVR.RTSP.Depayloader.H264.{FU, NAL, StapA}
  alias Membrane.{Buffer, H264}
  alias Membrane.H264.{AUSplitter, NALuParser}

  @frame_prefix <<1::32>>

  defmodule State do
    @moduledoc false
    alias Membrane.H264.{AUSplitter, NALuParser}

    defstruct nalu_parser: NALuParser.new(),
              au_splitter: AUSplitter.new(),
              sps: %{},
              pps: %{},
              fu_acc: nil,
              seen_key_frame?: false
  end

  @impl true
  def init(opts) do
    %State{}
    |> parse_initial_parameter_set(:sps, opts[:sps])
    |> parse_initial_parameter_set(:pps, opts[:pps])
  end

  @impl true
  def handle_packet(packet, state) do
    with {:ok, nalus, state} <- depayload(packet, state) do
      {:ok, parse(nalus, state)}
    end
  end

  @impl true
  def handle_discontinuity(%State{} = state) do
    %State{state | au_splitter: AUSplitter.new(), nalu_parser: NALuParser.new(), fu_acc: nil}
  end

  defp parse_initial_parameter_set(state, _parameter_set, nil), do: state

  defp parse_initial_parameter_set(%State{} = state, key, data) do
    id_key = if key == :sps, do: :seq_parameter_set_id, else: :pic_parameter_set_id

    data = maybe_add_prefix(data)
    {sps, nalu_parser} = NALuParser.parse(data, state.nalu_parser)

    %State{
      state
      | nalu_parser: nalu_parser,
        sps: Map.get(state, key) |> Map.put(sps.parsed_fields[id_key], sps)
    }
  end

  # depayloader
  defp depayload(packet, state) do
    with {:ok, {header, _payload} = nal} <- NAL.Header.parse_unit_header(packet.payload),
         unit_type = NAL.Header.decode_type(header),
         {:ok, {nalus, state}} <- handle_unit_type(unit_type, nal, packet, state) do
      {:ok, List.wrap(nalus), state}
    else
      {:error, reason} ->
        {:error, reason, %State{state | fu_acc: nil}}
    end
  end

  defp handle_unit_type(:single_nalu, _nal, packet, state) do
    result = buffer_output(packet.payload, packet, state)
    {:ok, result}
  end

  defp handle_unit_type(:fu_a, {header, data}, packet, state) do
    %{sequence_number: seq_num} = packet

    case FU.parse(data, seq_num, map_state_to_fu(state)) do
      {:ok, {data, type}} ->
        data = NAL.Header.add_header(data, 0, header.nal_ref_idc, type)
        result = buffer_output(data, packet, %State{state | fu_acc: nil})
        {:ok, result}

      {:incomplete, fu} ->
        result = {[], %State{state | fu_acc: fu}}
        {:ok, result}

      {:error, _reason} = error ->
        error
    end
  end

  defp handle_unit_type(:stap_a, {_header, data}, packet, state) do
    with {:ok, result} <- StapA.parse(data) do
      buffers = Enum.map(result, &{add_prefix(&1), packet.timestamp})
      {:ok, {buffers, state}}
    end
  end

  defp buffer_output(data, packet, state) do
    {{add_prefix(data), packet.timestamp}, state}
  end

  defp add_prefix(data), do: @frame_prefix <> data

  defp map_state_to_fu(%State{fu_acc: %FU{} = fu}), do: fu
  defp map_state_to_fu(_state), do: %FU{}

  # Parser
  defp parse(nalus, state) do
    {nalus, nalu_parser} =
      Enum.map_reduce(
        nalus,
        state.nalu_parser,
        &NALuParser.parse(elem(&1, 0), {nil, elem(&1, 1)}, &2)
      )

    {access_units, au_splitter} = AUSplitter.split(nalus, state.au_splitter)

    state = %{state | nalu_parser: nalu_parser, au_splitter: au_splitter}
    Enum.flat_map_reduce(access_units, state, &process_au(&1, &2))
  end

  defp process_au(au, state) do
    key_frame? = key_frame?(au)

    cond do
      key_frame? ->
        {stream_format, state} = get_stream_format(au, state)
        au = add_parameter_sets(au, state)
        {[stream_format, wrap_into_buffer(au)], %{state | seen_key_frame?: true}}

      state.seen_key_frame? ->
        {[wrap_into_buffer(au)], state}

      true ->
        {[], state}
    end
  end

  defp maybe_add_prefix(nalu) do
    case nalu do
      <<0, 0, 1, _rest::binary>> -> nalu
      <<0, 0, 0, 1, _rest::binary>> -> nalu
      nalu -> <<0, 0, 0, 1, nalu::binary>>
    end
  end

  defp add_parameter_sets(au, state) do
    au = Map.values(state.sps) ++ Map.values(state.pps) ++ au
    Enum.uniq_by(au, & &1.payload)
  end

  defp get_stream_format(au, state) do
    {sps, pps} =
      Enum.reduce(au, {nil, nil}, fn
        %{type: :sps} = nalu, {_sps, pps} -> {nalu, pps}
        %{type: :pps} = nalu, {sps, _pps} -> {sps, nalu}
        _nalu, {sps, pps} -> {sps, pps}
      end)

    stream_format = %H264{
      width: sps.parsed_fields.width,
      height: sps.parsed_fields.height,
      profile: sps.parsed_fields.profile,
      alignment: :au,
      nalu_in_metadata?: true,
      stream_structure: :annexb
    }

    state = %State{
      state
      | sps: Map.put(state.sps, sps.parsed_fields.seq_parameter_set_id, sps),
        pps: Map.put(state.pps, pps.parsed_fields.pic_parameter_set_id, pps)
    }

    {stream_format, state}
  end

  defp wrap_into_buffer(au) do
    {dts, pts} = List.last(au).timestamps

    Enum.reduce(au, <<>>, fn nalu, acc ->
      acc <> NALuParser.get_prefixed_nalu_payload(nalu, :annexb)
    end)
    |> then(fn payload ->
      %Buffer{
        dts: dts,
        pts: pts,
        payload: payload,
        metadata: prepare_au_metadata(au, key_frame?(au))
      }
    end)
  end

  defp key_frame?(au), do: Enum.any?(au, &(&1.type == :idr))

  defp prepare_au_metadata(nalus, is_keyframe?) do
    %{h264: %{key_frame?: is_keyframe?, nalus: Enum.map(nalus, & &1.type)}}
  end
end
