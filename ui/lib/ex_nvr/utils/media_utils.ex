defmodule ExNVR.MediaUtils do
  @moduledoc false

  alias Membrane.Buffer

  @spec get_hevc_dcr([binary()], [binary()], [binary()]) :: ExMP4.Box.Hvcc.t()
  def get_hevc_dcr(vpss, spss, ppss) do
    %{content: sps} = MediaCodecs.H265.parse_nalu(List.first(spss))

    <<constraint_indicator_flags::48>> =
      <<sps.progressive_source_flag::1, sps.interlaced_source_flag::1,
        sps.non_packed_constraint_flag::1, sps.frame_only_constraint_flag::1, 0::44>>

    %ExMP4.Box.Hvcc{
      vpss: vpss,
      spss: spss,
      ppss: ppss,
      profile_space: sps.profile_space,
      tier_flag: sps.tier_flag,
      profile_idc: sps.profile_idc,
      profile_compatibility_flags: sps.profile_compatibility_flag,
      constraint_indicator_flags: constraint_indicator_flags,
      level_idc: sps.level_idc,
      chroma_format_idc: sps.chroma_format_idc,
      bit_depth_chroma_minus8: sps.bit_depth_chroma_minus8,
      bit_depth_luma_minus8: sps.bit_depth_luma_minus8,
      temporal_id_nested: sps.temporal_id_nesting_flag,
      num_temporal_layers: sps.max_sub_layers_minus1,
      nalu_length_size: 4
    }
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
end
