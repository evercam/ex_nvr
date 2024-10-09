defmodule ExNVR.Pipeline.Output.StoragePipelineTest do
  @moduledoc false

  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias ExNVR.Pipeline.Output.Storage
  alias Membrane.Testing.{Pipeline, Source}

  @moduletag :tmp_dir

  defmodule Timestamper do
    @moduledoc false

    use Membrane.Filter

    def_input_pad :input, accepted_format: _any
    def_output_pad :output, accepted_format: _any

    @impl true
    def handle_init(_ctx, _opts), do: {[], nil}

    @impl true
    def handle_buffer(:input, buffer, _ctx, state) do
      buffer = %{buffer | metadata: Map.put(buffer.metadata, :timestamp, DateTime.utc_now())}
      {[buffer: {:output, buffer}], state}
    end
  end

  @h264_fixtures "../../../../fixtures/video-30-10s.h264" |> Path.expand(__DIR__)
  @h265_fixtures "../../../../fixtures/video-30-10s.h265" |> Path.expand(__DIR__)

  setup %{tmp_dir: tmp_dir} do
    %{device: camera_device_fixture(tmp_dir)}
  end

  test "Segment H264 stream and save recordings", %{device: device} do
    perform_test(device, @h264_fixtures)
  end

  test "Segment H265 stream and save recordings", %{device: device} do
    perform_test(device, @h265_fixtures)
  end

  defp perform_test(device, fixture) do
    pid = start_pipeline(device, fixture)

    assert_pipeline_notified(pid, :storage, {:segment_stored, :high, segment1})
    assert_pipeline_notified(pid, :storage, {:segment_stored, :high, segment2})
    assert_pipeline_notified(pid, :storage, {:segment_stored, :high, segment3})

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

  defp start_pipeline(device, filename) do
    parser =
      case Path.extname(filename) do
        ".h264" -> %Membrane.H264.Parser{generate_best_effort_timestamps: %{framerate: {20, 1}}}
        ".h265" -> %Membrane.H265.Parser{generate_best_effort_timestamps: %{framerate: {20, 1}}}
      end

    spec = [
      child(:source, %Source{output: chunk_file(filename)})
      |> child(:parser, parser)
      |> child(:timestamper, Timestamper)
      |> child(:storage, %Storage{
        device: device,
        target_segment_duration: 4
      })
    ]

    Pipeline.start_supervised!(spec: spec)
  end

  defp chunk_file(file) do
    File.read!(file)
    |> :binary.bin_to_list()
    |> Enum.chunk_every(100)
    |> Enum.map(&:binary.list_to_bin/1)
  end
end
