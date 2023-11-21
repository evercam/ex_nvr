defmodule ExNVR.Pipeline.Output.StoragePipelineTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias ExNVR.Pipeline.Output.Storage
  alias Membrane.Testing.{Pipeline, Source}

  @moduletag :tmp_dir

  @fixture_path "../../../../fixtures/video-30-10s.h264" |> Path.expand(__DIR__)

  setup do
    device = device_fixture()
    File.mkdir_p!(ExNVR.Utils.recording_dir(device))

    %{device: device}
  end

  test "Segment a stream and save recordings", %{device: device} do
    pid = start_pipeline(device)

    assert_pipeline_notified(pid, :storage, {:segment_stored, segment1})
    assert_pipeline_notified(pid, :storage, {:segment_stored, segment2})
    assert_pipeline_notified(pid, :storage, {:segment_stored, segment3})

    assert DateTime.diff(segment1.end_date, segment1.start_date) == 6
    assert DateTime.diff(segment2.end_date, segment2.start_date) == 6
    assert DateTime.diff(segment3.end_date, segment3.start_date) == 3

    assert {:ok, {recordings, _meta}} = ExNVR.Recordings.list()
    assert length(recordings) == 3

    assert recording_path(device, segment1.start_date) |> File.exists?()
    assert recording_path(device, segment2.start_date) |> File.exists?()
    assert recording_path(device, segment3.start_date) |> File.exists?()

    Pipeline.terminate(pid)
  end

  defp start_pipeline(device) do
    structure = [
      child(:source, %Source{output: chunk_file()})
      |> child(:parser, %Membrane.H264.Parser{
        generate_best_effort_timestamps: %{framerate: {20, 1}}
      })
      |> child(:storage, %Storage{
        device: device,
        target_segment_duration: 4
      })
    ]

    Pipeline.start_supervised!(structure: structure)
  end

  defp chunk_file() do
    File.read!(@fixture_path)
    |> :binary.bin_to_list()
    |> Enum.chunk_every(500)
    |> Enum.map(&:binary.list_to_bin/1)
  end

  defp recording_path(device, start_date) do
    device
    |> ExNVR.Utils.recording_dir()
    |> Path.join("#{DateTime.to_unix(start_date, :microsecond)}.mp4")
  end
end
