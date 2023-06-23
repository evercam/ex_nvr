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

  test "Snapshot is created from the video", %{
    device: device,
    recording: recording,
    tmp_dir: tmp_dir
  } do
    image_dest = Path.join(tmp_dir, "image")
    pid = prepare_pipeline(device, recording, image_dest)

    assert_end_of_stream(pid, :sink, :input, 5_000)

    assert File.exists?(image_dest <> "_0.jpeg")

    Testing.Pipeline.terminate(pid, blocking: true)
  end

  test "PNG Snapshot is created from the video", %{
    device: device,
    recording: recording,
    tmp_dir: tmp_dir
  } do
    image_dest = Path.join(tmp_dir, "image")
    pid = prepare_pipeline(device, recording, image_dest, format: :png)

    assert_end_of_stream(pid, :sink, :input, 5_000)

    assert File.exists?(image_dest <> "_0.png")

    Testing.Pipeline.terminate(pid, blocking: true)
  end

  defp prepare_pipeline(device, recording, image_destination, options \\ []) do
    options = [
      module: ExNVR.Pipelines.Snapshot,
      custom_args:
        [
          device_id: device.id,
          date: DateTime.add(recording.start_date, 3),
          destination: image_destination
        ]
        |> Keyword.merge(options)
    ]

    Testing.Pipeline.start_link_supervised!(options)
  end
end
