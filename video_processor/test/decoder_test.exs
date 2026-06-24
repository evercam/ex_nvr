defmodule ExNVR.AV.DecoderTest do
  use ExUnit.Case, async: true

  alias ExNVR.AV.{Decoder, Encoder, Frame}
  alias ExNVR.AV.VideoProcessor.NIF

  @h264_frame File.read!("test/fixtures/decoder/sample.h264")
  @h265_frame File.read!("test/fixtures/decoder/sample.h265")

  test "new/0" do
    assert decoder = Decoder.new(:h264)
    assert is_reference(decoder)

    assert decoder = Decoder.new(:hevc)
    assert is_reference(decoder)

    assert_raise(FunctionClauseError, fn -> Decoder.new(:vp8) end)
  end

  test "repeated failed constructions with an unknown codec raise a controlled error" do
    for _i <- 1..1000 do
      assert_raise ErlangError, ~r/unknown_codec/, fn ->
        NIF.new_decoder(:vp9, -1, -1, nil, 0)
      end
    end
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

    test "converted frames returned in the same batch keep their own pixels" do
      width = 64
      height = 64
      luma_values = [16, 56, 96, 136, 176, 216]

      encoder =
        Encoder.new(:h264,
          width: width,
          height: height,
          format: :yuv420p,
          time_base: {1, 25},
          max_b_frames: 2
        )

      packets =
        luma_values
        |> Enum.with_index()
        |> Enum.flat_map(fn {luma, pts} ->
          Encoder.encode(encoder, %Frame{data: solid_yuv420p(width, height, luma), pts: pts})
        end)
        |> Kernel.++(Encoder.flush(encoder))

      decoder = Decoder.new(:h264, out_format: :rgb24)

      batches =
        Enum.map(packets, &Decoder.decode(decoder, &1.data, pts: &1.pts)) ++
          [Decoder.flush(decoder)]

      # B-frame reordering must make at least one call return more than one frame,
      # otherwise this test doesn't exercise batched conversion.
      assert Enum.any?(batches, &(length(&1) > 1))

      frames = batches |> List.flatten() |> Enum.sort_by(& &1.pts)
      assert length(frames) == length(luma_values)

      for {frame, luma} <- Enum.zip(frames, luma_values) do
        # limited-range yuv420p with neutral chroma maps to gray (luma - 16) * 255 / 219
        expected = round((luma - 16) * 255 / 219)

        assert_in_delta dominant_byte(frame.data), expected, 5
      end
    end
  end

  defp decode_and_flush(decoder, sample) do
    Decoder.decode(decoder, sample) ++ Decoder.flush(decoder)
  end

  defp solid_yuv420p(width, height, luma) do
    chroma = :binary.copy(<<128>>, div(width, 2) * div(height, 2))
    :binary.copy(<<luma>>, width * height) <> chroma <> chroma
  end

  defp dominant_byte(data) do
    data
    |> :binary.bin_to_list()
    |> Enum.frequencies()
    |> Enum.max_by(fn {_byte, count} -> count end)
    |> elem(0)
  end
end
