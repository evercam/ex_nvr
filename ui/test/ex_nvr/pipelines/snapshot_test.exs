defmodule ExNVR.Pipelines.SnapshotTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import ExNVR.RecordingsFixtures

  alias ExNVR.Pipelines

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

  defp perform_test(device, recording, ref_path, method \\ :before) do
    assert {:ok, _sup_pid, _pid} =
             Pipelines.Snapshot.start(
               device: device,
               date: DateTime.add(recording.start_date, 3001, :millisecond),
               method: method
             )

    assert_receive {:snapshot, snapshot}, 1_000, "No snapshot received"
    assert snapshot == File.read!(ref_path), "Content not the same"
  end

  defp ref_path(encoding, method) do
    Path.expand("../../fixtures/images/#{encoding}/ref-#{method}.jpeg", __DIR__)
  end

  describe "snapshot is created" do
    test "from closest keyframe before specified date time", %{
      device: device,
      avc_recording: avc_recording,
      hevc_recording: hevc_recording
    } do
      perform_test(device, avc_recording, ref_path(:h264, "before-keyframe"))
      perform_test(device, hevc_recording, ref_path(:h265, "before-keyframe"))
    end

    test "with exact time", %{
      device: device,
      avc_recording: avc_recording,
      hevc_recording: hevc_recording
    } do
      perform_test(device, avc_recording, ref_path(:h264, "precise"), :precise)
      perform_test(device, hevc_recording, ref_path(:h265, "precise"), :precise)
    end
  end
end
