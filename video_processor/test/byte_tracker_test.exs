defmodule ExNVR.AV.ByteTrackerTest do
  use ExUnit.Case, async: true

  alias ExNVR.AV.ByteTracker
  alias ExNVR.AV.Hailo.Parsers.YoloV8.DetectedObject

  test "to_nif_inputs converts xyxy detections to tlwh tuples" do
    detections = [
      %DetectedObject{
        xmin: 10,
        ymin: 20,
        xmax: 40,
        ymax: 70,
        class_id: 8,
        class_name: "truck",
        score: 0.9
      }
    ]

    assert [{10.0, 20.0, 30.0, 50.0, 8, 0.9}] = ByteTracker.to_nif_inputs(detections)
  end

  test "update returns an empty list when tracker nif is unavailable" do
    assert [] = ByteTracker.update(nil, [])
  end
end
