defmodule ExNVR.AV.Hailo.Parsers.YoloV8Test do
  use ExUnit.Case, async: true

  alias ExNVR.AV.Hailo.Parsers.YoloV8
  alias ExNVR.AV.Hailo.Parsers.YoloV8.{DetectedObject, RawDetectedObject}

  test "parse decodes detections using class names" do
    output =
      <<
        1.0::float-32-little,
        0.1::float-32-little,
        0.2::float-32-little,
        0.4::float-32-little,
        0.6::float-32-little,
        0.95::float-32-little,
        0.0::float-32-little
      >>

    assert {:ok, detections} =
             YoloV8.parse(%{"nms" => output}, key: "nms", classes: %{0 => "person", 1 => "car"})

    assert [
             %RawDetectedObject{
               ymin: 0.1,
               xmin: 0.2,
               ymax: 0.4,
               xmax: 0.6,
               score: 0.95,
               class_id: 0,
               class_name: "person"
             }
           ] = detections
  end

  test "postprocess maps padded coordinates back to original frame size" do
    detections = [
      %RawDetectedObject{
        xmin: 0.25,
        ymin: 0.125,
        xmax: 0.75,
        ymax: 0.875,
        score: 0.95,
        class_id: 0,
        class_name: "person"
      }
    ]

    assert [
             %DetectedObject{
               xmin: 0,
               ymin: 0,
               xmax: 640,
               ymax: 480,
               class_name: "person"
             }
           ] = YoloV8.postprocess(detections, {480, 640})
  end
end
