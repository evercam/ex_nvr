defmodule ExNVRWeb.ViewUtilsTest do
  @moduledoc false

  use ExUnit.Case

  alias ExNVRWeb.ViewUtils

  test "humanize duration" do
    assert ViewUtils.humanize_duration(0) == "00:00:00.000"
    assert ViewUtils.humanize_duration(1010) == "00:00:01.010"
    assert ViewUtils.humanize_duration(168_909) == "00:02:48.909"
    assert ViewUtils.humanize_duration(156_512_690) == "43:28:32.690"
  end

  test "humanize size" do
    assert ViewUtils.humanize_size(10) == "10 B"
    assert ViewUtils.humanize_size(1000) == "0.98 KiB"
    assert ViewUtils.humanize_size(2_390_334) == "2.28 MiB"
    assert ViewUtils.humanize_size(42_390_334) == "40.43 MiB"
    assert ViewUtils.humanize_size(823_654_390_334) == "767.09 GiB"
  end

  test "humanize bitrate" do
    assert ViewUtils.humanize_bitrate(406) == "406 bps"
    assert ViewUtils.humanize_bitrate(1_406) == "1 kbps"
    assert ViewUtils.humanize_bitrate(67_806) == "67 kbps"
    assert ViewUtils.humanize_bitrate(8_754_674) == "8754 kbps"
  end
end
