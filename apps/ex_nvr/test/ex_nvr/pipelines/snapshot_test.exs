defmodule ExNVR.Pipelines.SnapshotTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import ExNVR.RecordingsFixtures

  alias ExNVR.Pipelines

  @moduletag :tmp_dir

  setup do
    device = device_fixture()
    File.mkdir!(ExNVR.Utils.recording_dir(device))

    recording =
      recording_fixture(device,
        start_date: ~U(2023-06-23 10:00:00Z),
        end_date: ~U(2023-06-23 10:00:05Z)
      )

    %{device: device, recording: recording}
  end

  defp perform_test(device, recording, ref_path, method \\ :before) do
    assert {:ok, _sup_pid, _pid} =
             Pipelines.Snapshot.start(
               device: device,
               date: DateTime.add(recording.start_date, 3),
               method: method
             )

    assert_receive {:snapshot, snapshot}, 1_000, "No snapshot received"
    assert snapshot == File.read!(ref_path)
  end

  describe "snapshot is created" do
    test "from closest keyframe before specified date time", %{
      device: device,
      recording: recording
    } do
      ref_path = "../../fixtures/images/ref_snapshot_before_keyframe.jpeg" |> Path.expand(__DIR__)
      perform_test(device, recording, ref_path)
    end

    test "with exact time", %{device: device, recording: recording} do
      ref_path = "../../fixtures/images/ref_snapshot_exact_time.jpeg" |> Path.expand(__DIR__)
      perform_test(device, recording, ref_path, :precise)
    end
  end
end
