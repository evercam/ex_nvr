defmodule ExNVR.Recordings.SnapshooterTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import ExNVR.RecordingsFixtures

  @moduletag :tmp_dir

  setup do
    device = device_fixture()

    File.mkdir!(ExNVR.Utils.recording_dir(device.id))

    recording =
      recording_fixture(device,
        start_date: ~U(2023-06-23 10:00:00Z),
        end_date: ~U(2023-06-23 10:00:05Z)
      )

    %{device: device, recording: recording}
  end

  test "get snapshot from closest keyframe before specified date time", %{
    device: device,
    recording: recording
  } do
    ref_path = "../../fixtures/images/ref_snapshot_before_keyframe.jpeg" |> Path.expand(__DIR__)

    assert {:ok, snapshot} =
             ExNVR.Recordings.Snapshooter.snapshot(
               recording,
               ExNVR.Utils.recording_dir(device.id),
               ~U(2023-06-23 10:00:03Z)
             )

    assert snapshot == File.read!(ref_path)
  end

  test "get snapshot at the specified date time", %{
    device: device,
    recording: recording
  } do
    ref_path = "../../fixtures/images/ref_snapshot_exact_time.jpeg" |> Path.expand(__DIR__)

    assert {:ok, snapshot} =
             ExNVR.Recordings.Snapshooter.snapshot(
               recording,
               ExNVR.Utils.recording_dir(device.id),
               ~U(2023-06-23 10:00:03Z),
               method: :precise
             )

    assert snapshot == File.read!(ref_path)
  end
end
