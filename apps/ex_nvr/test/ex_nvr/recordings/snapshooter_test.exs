defmodule ExNVR.Recordings.SnapshooterTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import ExNVR.RecordingsFixtures

  @moduletag :tmp_dir

  setup do
    device = device_fixture()
    File.mkdir_p!(ExNVR.Utils.recording_dir(device))

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

    assert {:ok, timestamp, snapshot} =
             ExNVR.Recordings.Snapshooter.snapshot(
               recording,
               ExNVR.Utils.recording_dir(device),
               ~U(2023-06-23 10:00:03Z)
             )

    assert snapshot == File.read!(ref_path)

    assert_in_delta(
      DateTime.to_unix(timestamp, :millisecond),
      DateTime.to_unix(~U(2023-06-23 10:00:02Z), :millisecond),
      100
    )
  end

  test "get snapshot at the specified date time", %{
    device: device,
    recording: recording
  } do
    ref_path = "../../fixtures/images/ref_snapshot_exact_time.jpeg" |> Path.expand(__DIR__)
    datetime = ~U(2023-06-23 10:00:03Z)

    assert {:ok, start_date, snapshot} =
             ExNVR.Recordings.Snapshooter.snapshot(
               recording,
               ExNVR.Utils.recording_dir(device),
               datetime,
               method: :precise
             )

    assert snapshot == File.read!(ref_path)
    assert DateTime.compare(start_date, datetime) == :eq
  end
end
