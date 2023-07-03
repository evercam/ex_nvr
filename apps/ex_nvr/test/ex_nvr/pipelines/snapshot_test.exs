defmodule ExNVR.Pipelines.SnapshotTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import ExNVR.RecordingsFixtures
  import Membrane.Testing.Assertions

  alias Membrane.Testing

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

  test "Snapshot is created from the video", %{device: device, recording: recording} do
    pid = prepare_pipeline(device, recording)

    assert_pipeline_notified(pid, :sink, {:snapshot, snapshot})
    Testing.Pipeline.terminate(pid)

    assert_receive {:snapshot, ^snapshot}, 1_000, "No snapshot received"
  end

  test "PNG Snapshot is created from the video", %{device: device, recording: recording} do
    pid = prepare_pipeline(device, recording, format: :png)

    assert_pipeline_notified(pid, :sink, {:snapshot, snapshot})
    Testing.Pipeline.terminate(pid)

    assert_receive {:snapshot, ^snapshot}, 1_000, "No snapshot received"
  end

  defp prepare_pipeline(device, recording, options \\ []) do
    options = [
      module: ExNVR.Pipelines.Snapshot,
      custom_args:
        [
          device_id: device.id,
          date: DateTime.add(recording.start_date, 3),
          caller: self()
        ]
        |> Keyword.merge(options)
    ]

    Testing.Pipeline.start_supervised!(options)
  end
end
