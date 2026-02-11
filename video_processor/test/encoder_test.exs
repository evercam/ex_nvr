defmodule ExNVR.AV.EncoderTest do
  use ExUnit.Case, async: true

  alias ExNVR.AV.{Encoder, Frame, Packet}

  describe "new/2" do
    test "new encoder" do
      assert encoder =
               Encoder.new(:h264,
                 width: 180,
                 height: 160,
                 format: :yuv420p,
                 time_base: {1, 90_000}
               )

      assert is_reference(encoder)
    end

    test "raises on invalid encoder" do
      assert_raise FunctionClauseError, fn -> Encoder.new(:hevc, []) end
    end
  end

  describe "encode/1" do
    setup do
      frame = %Frame{
        type: :video,
        data: File.read!("test/fixtures/encoder/frame_360x240.yuv"),
        format: :yuv420p,
        width: 360,
        height: 240,
        pts: 0
      }

      %{frame: frame}
    end

    test "encode a frame", %{frame: frame} do
      encoder =
        Encoder.new(:h264,
          width: 360,
          height: 240,
          format: :yuv420p,
          time_base: {1, 25}
        )

      assert [] = Encoder.encode(encoder, frame)

      assert [
               %Packet{
                 data: data,
                 dts: 0,
                 pts: 0,
                 keyframe?: true
               }
             ] = Encoder.flush(encoder)

      assert byte_size(data) > 0
    end

    test "encode multiple frames", %{frame: frame} do
      encoder =
        Encoder.new(:h264,
          width: 360,
          height: 240,
          format: :yuv420p,
          time_base: {1, 25},
          gop_size: 1
        )

      packets =
        Encoder.encode(encoder, frame) ++
          Encoder.encode(encoder, %{frame | pts: 1}) ++
          Encoder.encode(encoder, %{frame | pts: 2}) ++
          Encoder.flush(encoder)

      assert length(packets) == 3
      assert Enum.all?(packets, & &1.keyframe?)
    end

    test "no bframes inserted", %{frame: frame} do
      encoder =
        Encoder.new(:h264,
          width: 360,
          height: 240,
          format: :yuv420p,
          time_base: {1, 25},
          max_b_frames: 0
        )

      packets =
        Stream.iterate(frame, fn frame -> %{frame | pts: frame.pts + 1} end)
        |> Stream.take(20)
        |> Stream.transform(
          fn -> encoder end,
          fn frame, encoder ->
            {Encoder.encode(encoder, frame), encoder}
          end,
          fn encoder -> {Encoder.flush(encoder), encoder} end,
          fn _encoder -> :ok end
        )
        |> Enum.to_list()

      assert length(packets) == 20
      assert Enum.all?(packets, &(&1.dts == &1.pts)), "dts should be equal to pts"
    end
  end
end
