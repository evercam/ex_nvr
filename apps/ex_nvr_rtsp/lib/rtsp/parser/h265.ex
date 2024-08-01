defmodule ExNVR.RTSP.Parser.H265 do
  @moduledoc """
  Parse and assemble H265 NAL units into access units.
  """

  @behaviour ExNVR.RTSP.Parser

  require Membrane.H265.NALuTypes

  alias ExNVR.RTSP.H265.{AP, FU, NAL}
  alias Membrane.{Buffer, H265}
  alias Membrane.H265.{AUSplitter, NALuParser, NALuTypes}

  @frame_prefix <<1::32>>

  defmodule State do
    @moduledoc false

    alias Membrane.H265.{AUSplitter, NALuParser}

    defstruct nalu_parser: NALuParser.new(),
              au_splitter: AUSplitter.new(),
              vps: %{},
              sps: %{},
              pps: %{},
              fu_acc: nil,
              sprop_max_don_diff: 0,
              seen_key_frame?: false
  end

  @impl true
  def init(opts) do
    vpss = Keyword.get(opts, :vpss, []) |> Enum.map(&maybe_add_prefix/1)
    spss = Keyword.get(opts, :spss, []) |> Enum.map(&maybe_add_prefix/1)
    ppss = Keyword.get(opts, :ppss, []) |> Enum.map(&maybe_add_prefix/1)

    %State{}
    |> parse_parameter_sets(:vps, vpss)
    |> parse_parameter_sets(:sps, spss)
    |> parse_parameter_sets(:pps, ppss)
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

  # depayloader
  def depayload(packet, state) do
    with {:ok, {header, _payload} = nal} <- NAL.Header.parse_unit_header(packet.payload),
         unit_type = NAL.Header.decode_type(header),
         {:ok, {nalus, state}} <- handle_unit_type(unit_type, nal, packet, state) do
      {:ok, List.wrap(nalus), state}
    else
      {:error, reason} ->
        {:error, reason, %{state | fu_acc: nil}}
    end
  end

  defp handle_unit_type(:single_nalu, _nalu, packet, state) do
    result = buffer_output(packet.payload, packet, state)
    {:ok, result}
  end

  defp handle_unit_type(:fu, {header, data}, packet, state) do
    %{sequence_number: seq_num} = packet

    case FU.parse(data, seq_num, map_state_to_fu(state)) do
      {:ok, {data, type, _don}} ->
        data =
          NAL.Header.add_header(data, 0, type, header.nuh_layer_id, header.nuh_temporal_id_plus1)

        result = buffer_output(data, packet, %State{state | fu_acc: nil})
        {:ok, result}

      {:incomplete, fu} ->
        result = {[], %State{state | fu_acc: fu}}
        {:ok, result}

      {:error, _reason} = error ->
        error
    end
  end

  defp handle_unit_type(:ap, {_header, data}, packet, state) do
    with {:ok, nalus} <- AP.parse(data, state.sprop_max_don_diff > 0) do
      nalus = Enum.map(nalus, fn {nalu, _don} -> {add_prefix(nalu), packet.timestamp} end)
      {:ok, {nalus, state}}
    end
  end

  defp buffer_output(data, packet, state) do
    {{add_prefix(data), packet.timestamp}, state}
  end

  defp add_prefix(data), do: @frame_prefix <> data

  defp map_state_to_fu(%State{fu_acc: %FU{} = fu}), do: fu
  defp map_state_to_fu(state), do: %FU{donl?: state.sprop_max_don_diff > 0}

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

  defp parse_parameter_sets(state, _parameter_set_type, []), do: state

  defp parse_parameter_sets(state, :vps, vpss) do
    {vpss, nalu_parser} = NALuParser.parse_nalus(vpss, state.nalu_parser)

    %{
      state
      | vps: Map.new(vpss, &{&1.parsed_fields.video_parameter_set_id, &1}),
        nalu_parser: nalu_parser
    }
  end

  defp parse_parameter_sets(state, :sps, spss) do
    {spss, nalu_parser} = NALuParser.parse_nalus(spss, state.nalu_parser)

    %{
      state
      | sps: Map.new(spss, &{&1.parsed_fields.seq_parameter_set_id, &1}),
        nalu_parser: nalu_parser
    }
  end

  defp parse_parameter_sets(state, :pps, ppss) do
    {ppss, nalu_parser} = NALuParser.parse_nalus(ppss, state.nalu_parser)

    %{
      state
      | pps: Map.new(ppss, &{&1.parsed_fields.pic_parameter_set_id, &1}),
        nalu_parser: nalu_parser
    }
  end

  defp maybe_add_prefix(nalu) do
    case nalu do
      <<0, 0, 1, _rest::binary>> -> nalu
      <<0, 0, 0, 1, _rest::binary>> -> nalu
      nalu -> <<0, 0, 0, 1, nalu::binary>>
    end
  end

  defp add_parameter_sets(au, state) do
    au = Map.values(state.vps) ++ Map.values(state.sps) ++ Map.values(state.pps) ++ au
    Enum.uniq_by(au, & &1.payload)
  end

  defp get_stream_format(au, state) do
    parameter_sets =
      au
      |> Enum.filter(&(&1.type in [:vps, :sps, :pps]))
      |> Enum.reduce(%{vps: [], sps: [], pps: []}, fn nalu, pss ->
        Map.update!(pss, nalu.type, &[nalu | &1])
      end)

    sps = List.last(parameter_sets[:sps])

    stream_format = %H265{
      width: sps.parsed_fields.width,
      height: sps.parsed_fields.height,
      profile: sps.parsed_fields.profile,
      alignment: :au,
      nalu_in_metadata?: true,
      stream_structure: :annexb
    }

    state =
      Enum.reduce(parameter_sets, state, fn
        {:vps, nalus}, state ->
          nalus = Map.new(nalus, &{&1.parsed_fields.video_parameter_set_id, &1})
          %{state | vps: Map.merge(nalus, state.vps)}

        {:sps, nalus}, state ->
          nalus = Map.new(nalus, &{&1.parsed_fields.seq_parameter_set_id, &1})
          %{state | sps: Map.merge(nalus, state.sps)}

        {:pps, nalus}, state ->
          nalus = Map.new(nalus, &{&1.parsed_fields.pic_parameter_set_id, &1})
          %{state | pps: Map.merge(nalus, state.pps)}
      end)

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

  defp key_frame?(au), do: Enum.any?(au, &NALuTypes.is_irap_nalu_type(&1.type))

  defp prepare_au_metadata(nalus, is_keyframe?) do
    %{h265: %{key_frame?: is_keyframe?, nalus: Enum.map(nalus, & &1.type)}}
  end
end
