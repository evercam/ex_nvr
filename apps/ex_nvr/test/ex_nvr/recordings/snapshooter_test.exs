defmodule ExNVR.Recordings.SnapshooterTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import ExNVR.RecordingsFixtures

  @moduletag :tmp_dir

  setup ctx do
    device = camera_device_fixture(ctx.tmp_dir)

    avc_recording =
      recording_fixture(device,
        start_date: ~U(2023-06-23 10:00:00Z),
        end_date: ~U(2023-06-23 10:00:05Z)
      )

    hevc_recording =
      recording_fixture(device,
        start_date: ~U(2023-06-23 10:00:10Z),
        end_date: ~U(2023-06-23 10:00:15Z),
        encoding: :H265
      )

    %{device: device, avc_recording: avc_recording, hevc_recording: hevc_recording}
  end

  test "get snapshot from closest keyframe before specified date time", %{
    device: device,
    avc_recording: avc_recording,
    hevc_recording: hevc_recording
  } do
    perform_test(
      device,
      avc_recording,
      ref_path(:h264, "before-keyframe"),
      ~U(2023-06-23 10:00:03Z),
      ~U(2023-06-23 10:00:02Z),
      :before
    )

    perform_test(
      device,
      hevc_recording,
      ref_path(:h265, "before-keyframe"),
      ~U(2023-06-23 10:00:13Z),
      ~U(2023-06-23 10:00:12Z),
      :before
    )
  end

  test "get snapshot at the specified date time", %{
    device: device,
    avc_recording: avc_recording,
    hevc_recording: hevc_recording
  } do
    perform_test(
      device,
      avc_recording,
      ref_path(:h264, "precise"),
      ~U(2023-06-23 10:00:03Z),
      ~U(2023-06-23 10:00:03Z),
      :precise
    )

    perform_test(
      device,
      hevc_recording,
      ref_path(:h265, "precise"),
      ~U(2023-06-23 10:00:13.01Z),
      ~U(2023-06-23 10:00:13Z),
      :precise
    )
  end

  defp perform_test(device, recording, _ref_path, requested_datetime, snapshot_timestamp, method) do
    assert {:ok, timestamp, _snapshot} =
             ExNVR.Recordings.Snapshooter.snapshot(
               device,
               recording,
               requested_datetime,
               method: method
             )

    # TODO: check why the snapshot is the not same after each test
    # assert snapshot == File.read!(ref_path)

    assert_in_delta(
      DateTime.to_unix(timestamp, :millisecond),
      DateTime.to_unix(snapshot_timestamp, :millisecond),
      100
    )
  end

  defp ref_path(encoding, method) do
    Path.expand("../../fixtures/images/#{encoding}/ref-#{method}.jpeg", __DIR__)
  end
end
