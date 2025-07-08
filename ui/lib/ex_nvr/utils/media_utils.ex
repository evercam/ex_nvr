defmodule ExNVR.MediaUtils do
  @moduledoc false

  alias MediaCodecs.H265.NALU
  alias Membrane.Buffer

  @default_video_timescale 90_000

  @spec get_hevc_dcr([binary()], [binary()], [binary()]) :: ExMP4.Box.Hvcc.t()
  def get_hevc_dcr(vpss, spss, ppss) do
    sps = NALU.SPS.parse(List.first(spss))
    profile = sps.profile_tier_level

    <<constraint_indicator_flags::48>> =
      <<profile.progressive_source_flag::1, profile.interlaced_source_flag::1,
        profile.non_packed_constraint_flag::1, profile.frame_only_constraint_flag::1, 0::44>>

    %ExMP4.Box.Hvcc{
      vpss: vpss,
      spss: spss,
      ppss: ppss,
      profile_space: profile.profile_space,
      tier_flag: profile.tier_flag,
      profile_idc: profile.profile_idc,
      profile_compatibility_flags: profile.profile_compatibility_flag,
      constraint_indicator_flags: constraint_indicator_flags,
      level_idc: profile.level_idc,
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

  @spec track_from_stream_format(module()) :: ExMP4.Track.t()
  def track_from_stream_format(stream_format) do
    media =
      case stream_format do
        %Membrane.H264{} -> :h264
        %Membrane.H265{} -> :h265
      end

    %ExMP4.Track{
      type: :video,
      media: media,
      width: stream_format.width,
      height: stream_format.height,
      timescale: @default_video_timescale
    }
  end

  @spec to_annexb(binary() | [binary()]) :: binary()
  def to_annexb(au) when is_list(au), do: Enum.map_join(au, &<<1::32, &1::binary>>)
  def to_annexb(au), do: au
end
