defmodule ExNVR.Pipeline.Output.StorageV2.MediaUtils do
  @moduledoc false

  alias Membrane.Buffer
  alias Membrane.H265.NALuParser

  @nalu_prefixes [<<0, 0, 1>>, <<0, 0, 0, 1>>]

  @doc """
  Build a priv data mp4 box (`Avcc` or `Hvcc`) from keyframe buffer
  """
  @spec get_priv_data(Buffer.t()) :: ExMP4.Box.t()
  def get_priv_data(buffer) do
    {vpss, spss, ppss} =
      :binary.split(buffer.payload, @nalu_prefixes, [:global])
      |> Enum.reject(&(&1 == ""))
      |> Enum.zip(get_nalu_types(buffer.metadata))
      |> Enum.reduce({[], [], []}, fn
        {data, :vps}, {vpss, spss, ppss} -> {[data | vpss], spss, ppss}
        {data, :sps}, {vpss, spss, ppss} -> {vpss, [data | spss], ppss}
        {data, :pps}, {vpss, spss, ppss} -> {vpss, spss, [data | ppss]}
        _element, acc -> acc
      end)
      |> then(fn {vpss, spss, ppss} ->
        {Enum.reverse(vpss), Enum.reverse(spss), Enum.reverse(ppss)}
      end)

    if Map.has_key?(buffer.metadata, :h264),
      do: ExMP4.Box.Avcc.new(spss, ppss),
      else: get_hevc_dcr(vpss, spss, ppss)
  end

  @spec convert_annexb_to_elementary_stream(Buffer.t()) :: binary()
  def convert_annexb_to_elementary_stream(buffer) do
    :binary.split(buffer.payload, @nalu_prefixes, [:global])
    |> Stream.reject(&(&1 == ""))
    |> Stream.zip(get_nalu_types(buffer.metadata))
    |> Stream.reject(fn {_data, type} -> type in [:vps, :sps, :pps] end)
    |> Stream.map(fn {data, _type} -> <<byte_size(data)::32, data::binary>> end)
    |> Enum.join()
  end

  defp get_nalu_types(%{h264: %{nalus: nalus}}), do: nalus
  defp get_nalu_types(%{h265: %{nalus: nalus}}), do: nalus

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
