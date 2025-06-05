defmodule ExNVR.MediaUtils do
  @moduledoc false

  alias ExMP4.Box
  alias Membrane.Buffer
  alias Membrane.H265.NALuParser

  @nalu_prefixes [<<0, 0, 1>>, <<0, 0, 0, 1>>]

  @doc """
  Build a priv data mp4 box (`Avcc` or `Hvcc`) from keyframe buffer
  """
  @spec get_priv_data(Buffer.t()) :: ExMP4.Box.t()
  def get_priv_data(buffer) do
    codec = if Map.has_key?(buffer.metadata, :h264), do: :h264, else: :h265

    {vpss, spss, ppss} =
      :binary.split(buffer.payload, @nalu_prefixes, [:global])
      |> Enum.reject(&(&1 == "" or not pss?(codec, &1)))
      |> Enum.map(&{&1, pss_type(codec, &1)})
      |> Enum.reduce({[], [], []}, fn
        {data, :vps}, {vpss, spss, ppss} -> {[data | vpss], spss, ppss}
        {data, :sps}, {vpss, spss, ppss} -> {vpss, [data | spss], ppss}
        {data, :pps}, {vpss, spss, ppss} -> {vpss, spss, [data | ppss]}
        _element, acc -> acc
      end)
      |> then(fn {vpss, spss, ppss} ->
        {Enum.reverse(vpss), Enum.reverse(spss), Enum.reverse(ppss)}
      end)

    if codec == :h264,
      do: Box.Avcc.new(spss, ppss),
      else: get_hevc_dcr(vpss, spss, ppss)
  end

  @spec convert_annexb_to_elementary_stream(Buffer.t(), :h264 | :h265) :: binary()
  def convert_annexb_to_elementary_stream(buffer, codec) do
    :binary.split(buffer.payload, @nalu_prefixes, [:global])
    |> Stream.reject(&(&1 == "" or pss?(codec, &1)))
    |> Stream.map(&<<byte_size(&1)::32, &1::binary>>)
    |> Enum.join()
  end

  @spec decode_last(Enumerable.t(Buffer.t() | ExMP4.Sample.t()), Xav.Decoder.t()) :: Buffer.t()
  def decode_last(buffers, decoder) do
    buffers
    |> Stream.transform(
      fn -> decoder end,
      fn packet, decoder ->
        case Xav.Decoder.decode(decoder, packet.payload, pts: packet.pts) do
          {:ok, frame} -> {[frame], decoder}
          _other -> {[], decoder}
        end
      end,
      &Xav.Decoder.flush!/1
    )
    |> Enum.reverse()
    |> hd()
  end

  defp pss?(:h264, <<_prefix::3, type::5, _rest::binary>>) when type == 7 or type == 8, do: true
  defp pss?(:h265, <<0::1, type::6, _rest::bitstring>>) when type in 32..34, do: true
  defp pss?(_codec, _nalu), do: false

  defp pss_type(:h264, <<_prefix::3, 7::5, _rest::binary>>), do: :sps
  defp pss_type(:h264, <<_prefix::3, 8::5, _rest::binary>>), do: :pps
  defp pss_type(:h265, <<0::1, 32::6, _rest::bitstring>>), do: :vps
  defp pss_type(:h265, <<0::1, 33::6, _rest::bitstring>>), do: :sps
  defp pss_type(:h265, <<0::1, 34::6, _rest::bitstring>>), do: :pps

  defp get_hevc_dcr(vpss, spss, ppss) do
    {sps, _nalu_parser} = NALuParser.parse(<<0, 0, 1, List.last(spss)::binary>>, NALuParser.new())

    %Membrane.H26x.NALu{
      parsed_fields: %{
        profile_space: profile_space,
        tier_flag: tier_flag,
        profile_idc: profile_idc,
        profile_compatibility_flag: profile_compatibility_flag,
        progressive_source_flag: progressive_source_flag,
        interlaced_source_flag: interlaced_source_flag,
        non_packed_constraint_flag: non_packed_constraint_flag,
        frame_only_constraint_flag: frame_only_constraint_flag,
        level_idc: level_idc,
        chroma_format_idc: chroma_format_idc,
        bit_depth_luma_minus8: bit_depth_luma_minus8,
        bit_depth_chroma_minus8: bit_depth_chroma_minus8,
        temporal_id_nesting_flag: temporal_id_nested,
        max_sub_layers_minus1: num_temporal_layers
      }
    } = sps

    <<constraint_indicator_flags::48>> =
      <<progressive_source_flag::1, interlaced_source_flag::1, non_packed_constraint_flag::1,
        frame_only_constraint_flag::1, 0::44>>

    %ExMP4.Box.Hvcc{
      vpss: vpss,
      spss: spss,
      ppss: ppss,
      profile_space: profile_space,
      tier_flag: tier_flag,
      profile_idc: profile_idc,
      profile_compatibility_flags: profile_compatibility_flag,
      constraint_indicator_flags: constraint_indicator_flags,
      level_idc: level_idc,
      chroma_format_idc: chroma_format_idc,
      bit_depth_chroma_minus8: bit_depth_chroma_minus8,
      bit_depth_luma_minus8: bit_depth_luma_minus8,
      temporal_id_nested: temporal_id_nested,
      num_temporal_layers: num_temporal_layers,
      nalu_length_size: 4
    }
  end
end
