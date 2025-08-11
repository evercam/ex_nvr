defmodule ExNVR.AV.DecoderTest do
  use ExUnit.Case, async: true

  alias ExNVR.AV.{Decoder, Frame}

  @h264_frame File.read!("test/fixtures/decoder/sample.h264")
  @h265_frame File.read!("test/fixtures/decoder/sample.h265")

  test "new/0" do
    assert decoder = Decoder.new(:h264)
    assert is_reference(decoder)

    assert decoder = Decoder.new(:hevc)
    assert is_reference(decoder)

    assert_raise(FunctionClauseError, fn -> Decoder.new(:vp8) end)
  end

  describe "decode/2" do
    test "h264 video" do
      decoder = Decoder.new(:h264)

      assert [%Frame{width: 1280, height: 720, pts: 0, format: :yuv420p}] =
               decode_and_flush(decoder, @h264_frame)
    end

    test "hevc video" do
      decoder = Decoder.new(:hevc)

      assert [%Frame{width: 1920, height: 1080, pts: 0, format: :yuv420p}] =
               decode_and_flush(decoder, @h265_frame)
    end

    test "convert video frame" do
      decoder = Decoder.new(:h264, out_format: :rgb24)

      assert [%Frame{width: 1280, height: 720, pts: 0, data: frame, format: :rgb24}] =
               decode_and_flush(decoder, @h264_frame)

      assert byte_size(frame) == 1280 * 720 * 3
    end

    test "scale video frame" do
      decoder = Decoder.new(:hevc, out_width: 240, out_height: 180)

      assert [%Frame{width: 240, height: 180, pts: 0, data: frame, format: :yuv420p}] =
               decode_and_flush(decoder, @h265_frame)

      assert byte_size(frame) == 240 * 180 * 3 / 2
    end
  end

  defp decode_and_flush(decoder, sample) do
    Decoder.decode(decoder, sample) ++ Decoder.flush(decoder)
  end
end
