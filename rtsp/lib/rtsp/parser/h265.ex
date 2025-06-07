defmodule ExNVR.RTSP.Parser.H265 do
  @moduledoc """
  Parse and assemble H265 NAL units into access units.
  """

  @behaviour ExNVR.RTSP.Parser

  alias ExNVR.RTSP.Depayloader.H265.{AP, FU, NAL}
  alias ExNVR.RTSP.Parser.HEVC.SPS
  alias Membrane.{Buffer, H265}

  @frame_prefix <<1::32>>

  defmodule State do
    @moduledoc false

    defstruct vps: [],
              sps: [],
              pps: [],
              fu_acc: nil,
              sprop_max_don_diff: 0,
              seen_key_frame?: false,
              access_unit: [],
              timestamp: nil
  end

  @impl true
  def init(opts) do
    vpss = Keyword.get(opts, :vpss, []) |> Enum.map(&maybe_strip_prefix/1)
    spss = Keyword.get(opts, :spss, []) |> Enum.map(&maybe_strip_prefix/1)
    ppss = Keyword.get(opts, :ppss, []) |> Enum.map(&maybe_strip_prefix/1)

    %State{vps: vpss, sps: spss, pps: ppss}
  end

  @impl true
  def handle_packet(packet, state) do
    with {:ok, nalus, state} <- depayload(packet, state) do
      {:ok, parse(nalus, state)}
    end
  end

  @impl true
  def handle_discontinuity(%State{} = state) do
    %State{state | fu_acc: nil, access_unit: [], timestamp: nil}
  end

  # depayloader
  def depayload(packet, state) do
    with {:ok, {header, _payload} = nal} <- NAL.Header.parse_unit_header(packet.payload),
         unit_type = NAL.Header.decode_type(header),
         {:ok, nalus, state} <- handle_unit_type(unit_type, nal, packet, state) do
      {:ok, nalus, state}
    else
      {:error, reason} ->
        {:error, reason, %{state | fu_acc: nil}}
    end
  end

  defp handle_unit_type(:single_nalu, _nalu, packet, state) do
    {:ok, {[packet.payload], packet.timestamp}, state}
  end

  defp handle_unit_type(:fu, {header, data}, packet, state) do
    %{sequence_number: seq_num} = packet

    case FU.parse(data, seq_num, map_state_to_fu(state)) do
      {:ok, {data, type, _don}} ->
        data =
          NAL.Header.add_header(data, 0, type, header.nuh_layer_id, header.nuh_temporal_id_plus1)

        {:ok, {[data], packet.timestamp}, %State{state | fu_acc: nil}}

      {:incomplete, fu} ->
        {:ok, {[], packet.timestamp}, %State{state | fu_acc: fu}}

      {:error, _reason} = error ->
        error
    end
  end

  defp handle_unit_type(:ap, {_header, data}, packet, state) do
    with {:ok, nalus} <- AP.parse(data, state.sprop_max_don_diff > 0) do
      {:ok, {nalus, packet.timestamp}, state}
    end
  end

  defp map_state_to_fu(%State{fu_acc: %FU{} = fu}), do: fu
  defp map_state_to_fu(state), do: %FU{donl?: state.sprop_max_don_diff > 0}

  # Parser
  defp parse({[], _timestamp}, state), do: {[], state}

  defp parse({nalus, timestamp}, state) do
    if timestamp != state.timestamp do
      {buffers, state} = process_au(state)
      {buffers, %{state | timestamp: timestamp, access_unit: nalus}}
    else
      {[], %{state | access_unit: state.access_unit ++ nalus}}
    end
  end

  defp process_au(state) do
    key_frame? = key_frame?(state.access_unit)

    cond do
      key_frame? ->
        state =
          state
          |> get_parameter_sets()
          |> add_parameter_sets()

        {stream_format, state} = get_stream_format(state)
        {[stream_format, wrap_into_buffer(state)], %{state | seen_key_frame?: true}}

      state.seen_key_frame? ->
        {[wrap_into_buffer(state)], state}

      true ->
        {[], state}
    end
  end

  defp get_parameter_sets(%{access_unit: au} = state) do
    Enum.reduce(au, state, fn
      <<_::1, 32::6, _rest::bitstring>> = vps, state ->
        %{state | vps: Enum.uniq([vps | state.vps])}

      <<_::1, 33::6, _rest::bitstring>> = sps, state ->
        %{state | sps: Enum.uniq([sps | state.sps])}

      <<_::1, 34::6, _rest::bitstring>> = pps, state ->
        %{state | pps: Enum.uniq([pps | state.pps])}

      _nalu, state ->
        state
    end)
  end

  defp maybe_strip_prefix(<<0, 0, 1, nalu::binary>>), do: nalu
  defp maybe_strip_prefix(<<0, 0, 0, 1, nalu::binary>>), do: nalu
  defp maybe_strip_prefix(nalu), do: nalu

  defp add_parameter_sets(state) do
    [state.vps, state.sps, state.pps, state.access_unit]
    |> Enum.concat()
    |> then(&%{state | access_unit: &1})
  end

  defp get_stream_format(state) do
    sps = state.sps |> List.first() |> SPS.parse()
    {width, height} = SPS.video_resolution(sps)

    stream_format = %H265{
      width: width,
      height: height,
      profile: SPS.profile(sps),
      alignment: :au,
      stream_structure: :annexb
    }

    {stream_format, state}
  end

  defp wrap_into_buffer(state) do
    %Buffer{
      dts: state.timestamp,
      pts: state.timestamp,
      payload: Enum.map_join(state.access_unit, &(@frame_prefix <> &1)),
      metadata: %{h265: %{key_frame?: key_frame?(state.access_unit)}}
    }
  end

  defp key_frame?(au),
    do: Enum.any?(au, fn <<_::1, type::6, _rest::bitstring>> -> type in 16..21 end)
end
