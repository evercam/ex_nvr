defmodule ExNVR.RTSP.Parser.HEVC.SPS do
  @moduledoc """
  Module responsible for parsing `hevc` sps.
  """

  defstruct [
    :vps_id,
    :max_sub_layers_minus1,
    :temporal_id_nesting_flag,
    :profile_space,
    :tier_flag,
    :profile_idc,
    :profile_compatibility_flag,
    :progressive_source_flag,
    :interlaced_source_flag,
    :non_packed_constraint_flag,
    :frame_only_constraint_flag,
    :level_idc,
    :sps_id,
    :chroma_format_idc,
    :pic_width_in_luma_samples,
    :pic_height_in_luma_samples,
    :conformance_window,
    :bit_depth_luma_minus8,
    :bit_depth_chroma_minus8
  ]

  def parse(<<header::16, nalu_body::binary>>) do
    data = :binary.split(nalu_body, <<0, 0, 3>>, [:global]) |> Enum.join(<<0, 0>>)
    do_parse(data)
  end

  def video_resolution(%__MODULE__{conformance_window: nil} = sps) do
    {sps.pic_width_in_luma_samples, sps.pic_height_in_luma_samples}
  end

  def video_resolution(%__MODULE__{} = sps) do
    {sub_width_c, sub_height_c} =
      case sps.chroma_format_idc do
        0 -> {1, 1}
        1 -> {2, 2}
        2 -> {2, 1}
        3 -> {1, 1}
      end

    [left, right, top, bottom] = sps.conformance_window

    {sps.pic_width_in_luma_samples - sub_width_c * (right + left),
     sps.pic_height_in_luma_samples - sub_height_c * (bottom + top)}
  end

  def profile(%__MODULE__{profile_idc: 1}), do: :main
  def profile(%__MODULE__{profile_idc: 2}), do: :main_10
  def profile(%__MODULE__{profile_idc: 3}), do: :main_still_picture
  def profile(%__MODULE__{profile_idc: 4}), do: :rext

  defp do_parse(
         <<vps_id::4, max_sub_layers_minus1::3, temporal_id_nesting_flag::1, profile_space::2,
           tier_flag::1, profile_idc::5, profile_compatibility_flag::32,
           progressive_source_flag::1, interlaced_source_flag::1, non_packed_constraint_flag::1,
           frame_only_constraint_flag::1, _reserved_44bits::44, level_idc::8, rest::binary>>
       ) do
    {sps_id, rest} = exp_golomb_integer(rest)
    {chroma_format_idc, rest} = exp_golomb_integer(rest)
    rest = seperate_colour_plane(chroma_format_idc, rest)
    {pic_width_in_luma_samples, rest} = exp_golomb_integer(rest)
    {pic_height_in_luma_samples, rest} = exp_golomb_integer(rest)
    {conformance_window, rest} = conformance_window(rest)
    {bit_depth_luma_minus8, rest} = exp_golomb_integer(rest)
    {bit_depth_chroma_minus8, _rest} = exp_golomb_integer(rest)

    %__MODULE__{
      vps_id: vps_id,
      max_sub_layers_minus1: max_sub_layers_minus1,
      temporal_id_nesting_flag: temporal_id_nesting_flag,
      profile_space: profile_space,
      tier_flag: tier_flag,
      profile_idc: profile_idc,
      profile_compatibility_flag: profile_compatibility_flag,
      progressive_source_flag: progressive_source_flag,
      interlaced_source_flag: interlaced_source_flag,
      non_packed_constraint_flag: non_packed_constraint_flag,
      frame_only_constraint_flag: frame_only_constraint_flag,
      level_idc: level_idc,
      sps_id: sps_id,
      chroma_format_idc: chroma_format_idc,
      pic_width_in_luma_samples: pic_width_in_luma_samples,
      pic_height_in_luma_samples: pic_height_in_luma_samples,
      conformance_window: conformance_window,
      bit_depth_luma_minus8: bit_depth_luma_minus8,
      bit_depth_chroma_minus8: bit_depth_chroma_minus8
    }
  end

  defp conformance_window(<<1::1, rest::bitstring>>) do
    {left_offset, rest} = exp_golomb_integer(rest)
    {right_offset, rest} = exp_golomb_integer(rest)
    {top_offset, rest} = exp_golomb_integer(rest)
    {bottom_offset, rest} = exp_golomb_integer(rest)

    {[left_offset, right_offset, top_offset, bottom_offset], rest}
  end

  defp conformance_window(rest), do: {nil, rest}

  defp seperate_colour_plane(3, <<_::1, rest::bitstring>>), do: rest
  defp seperate_colour_plane(_chroma_format_idc, rest), do: rest

  defp exp_golomb_integer(zeros_count \\ 0, <<0::1, data::bitstring>>) do
    exp_golomb_integer(zeros_count + 1, data)
  end

  defp exp_golomb_integer(zeros_count, data) do
    <<number::size(zeros_count + 1), data::bitstring>> = data
    {number - 1, data}
  end
end
