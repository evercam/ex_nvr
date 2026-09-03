defmodule ExNVRWeb.ExportFootageLiveTest do
  use ExUnit.Case, async: true

  alias ExNVR.Disk
  alias ExNVRWeb.ExportFootageLive, as: Live

  describe "format_bytes/1" do
    test "picks the largest unit that stays >= 1" do
      assert Live.format_bytes(nil) == "unknown"
      assert Live.format_bytes(512) == "512 B"
      assert Live.format_bytes(2048) == "2.0 KiB"
      assert Live.format_bytes(5 * 1024 * 1024) == "5.0 MiB"
      assert Live.format_bytes(3 * 1024 * 1024 * 1024) == "3.0 GiB"
      assert Live.format_bytes(2 * 1024 * 1024 * 1024 * 1024) == "2.0 TiB"
    end
  end

  describe "percent_used/1" do
    test "computes used percentage from size/avail" do
      fs = %Disk.FS{size: 1000, avail: 250}
      assert Live.percent_used(fs) == 75.0
    end

    test "defaults to 0.0 when size is missing or zero" do
      assert Live.percent_used(%Disk.FS{size: nil, avail: nil}) == 0.0
      assert Live.percent_used(%Disk.FS{size: 0, avail: 0}) == 0.0
    end
  end
end
