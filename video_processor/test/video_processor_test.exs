defmodule ExNVR.AV.ViodeoProcessorTest do
  use ExUnit.Case, async: true

  alias ExNVR.AV.VideoProcessor

  describe "new_converter/1" do
    test "new converter" do
      assert converter =
               VideoProcessor.new_converter(
                 in_width: 640,
                 in_height: 480,
                 in_format: :yuv420p,
                 out_width: 320,
                 out_height: 240,
                 out_format: :rgb24,
                 pad?: false
               )

      assert is_reference(converter)
    end
  end

  describe "convert/2" do
    setup do
      converter =
        VideoProcessor.new_converter(
          in_width: 360,
          in_height: 240,
          in_format: :yuv420p,
          out_width: 180,
          out_height: 120,
          out_format: :rgb24,
          pad?: false
        )

      %{converter: converter}
    end

    test "convert a frame", %{converter: converter} do
      data = File.read!("test/fixtures/encoder/frame_360x240.yuv")

      converted_data = VideoProcessor.convert(converter, data)
      assert is_binary(converted_data)
      assert byte_size(converted_data) == 180 * 120 * 3
    end
  end
end
