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

  setup %{tmp_dir: tmp_dir} do
    device = device_fixture(%{settings: %{storage_address: tmp_dir}})

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

    assert ExNVR.Recordings.recording_path(device, segment1) |> File.exists?()
    assert ExNVR.Recordings.recording_path(device, segment2) |> File.exists?()
    assert ExNVR.Recordings.recording_path(device, segment3) |> File.exists?()

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
end
