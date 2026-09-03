defmodule ExNVR.Pipeline.Output.Storage.StoragePipelineTest do
  @moduledoc false

  use ExNVR.DataCase
  use Mimic

  import ExNVR.DevicesFixtures
  import ExUnit.CaptureLog
  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias ExNVR.Model.Device
  alias ExNVR.Pipeline.Output.Storage
  alias ExNVR.Support.SyncEvent
  alias Membrane.Testing.{Pipeline, Source}

  @moduletag :tmp_dir

  defmodule Timestamper do
    @moduledoc false

    use Membrane.Filter

    def_input_pad :input, accepted_format: _any
    def_output_pad :output, accepted_format: _any

    def_options jump: [
                  spec: nil | {non_neg_integer(), integer()},
                  default: nil,
                  description: """
                  `{index, offset_ms}` - add `offset_ms` to the wall clock timestamp
                  of all buffers starting from the buffer at `index` (zero based).

                  Simulates a clock jump between the camera and the NVR.
                  """
                ]

    @impl true
    def handle_init(_ctx, opts), do: {[], %{jump: opts.jump, count: 0}}

    @impl true
    def handle_buffer(:input, buffer, _ctx, state) do
      # flatten metadata to match the format created by `ex_nvr_rtsp`
      metadata =
        buffer.metadata
        |> update_nalus_metadata()
        |> Map.put(:timestamp, System.os_time(:millisecond) + offset(state))

      buffer = %{buffer | metadata: metadata}
      {[buffer: {:output, buffer}], %{state | count: state.count + 1}}
    end

    @impl true
    def handle_event(:input, %SyncEvent{} = event, _ctx, state) do
      # by the time this event is handled, all preceding buffers were
      # already sent downstream
      {[event: {:output, event}, notify_parent: :all_buffers_sent], state}
    end

    @impl true
    def handle_event(_pad, event, _ctx, state), do: {[forward: event], state}

    defp offset(%{jump: {index, offset_ms}, count: count}) when count >= index, do: offset_ms
    defp offset(_state), do: 0

    defp update_nalus_metadata(%{h264: %{nalus: nalus}} = metadata) do
      nalus = Enum.map(nalus, & &1.metadata.h264.type)
      put_in(metadata, [:h264, :nalus], nalus)
    end

    defp update_nalus_metadata(%{h265: %{nalus: nalus}} = metadata) do
      nalus = Enum.map(nalus, & &1.metadata.h265.type)
      put_in(metadata, [:h265, :nalus], nalus)
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

  describe "discontinuity" do
    test "discontinuity event finalizes the segment and starts a new run", %{device: device} do
      perform_discontinuity_test(device, %Membrane.Event.Discontinuity{})
    end

    test "stream closed event finalizes the segment and starts a new run", %{device: device} do
      perform_discontinuity_test(device, %ExNVR.Pipeline.Event.StreamClosed{})
    end
  end

  describe "terminate request" do
    test "flushes the in-flight segment to disk and database", %{device: device} do
      chunks = chunk_file(@h264_fixtures)

      # feed only ~1/8 of the stream — well under one 4 s segment — and never
      # send end of stream, so the only way the in-flight segment reaches
      # disk is the terminate request below
      actions =
        buffer_actions(Enum.take(chunks, div(length(chunks), 8))) ++
          [event: {:output, %SyncEvent{}}]

      pid = start_pipeline(device, @h264_fixtures, source: actions_source(actions))

      assert_pipeline_notified(pid, :timestamper, :all_buffers_sent)

      # the target segment duration was not reached, nothing is saved yet
      assert {:ok, {[], _meta}} = ExNVR.Recordings.list()

      Pipeline.terminate(pid)

      assert {:ok, {[recording], _meta}} = ExNVR.Recordings.list()

      duration = DateTime.diff(recording.end_date, recording.start_date, :millisecond)
      assert duration > 0
      assert duration < 4_000

      assert_valid_recording(device, recording, :h264)

      assert [run] = ExNVR.Recordings.list_runs(%{device_id: device.id})
      assert run.id == recording.run_id
      refute run.active
    end
  end

  describe "timestamp correction" do
    test "drift beyond the correction window is clamped to the 30 ms cap", %{device: device} do
      pid = start_pipeline(device, @h264_fixtures, correct_timestamp: true)

      assert_end_of_stream(pid, :storage)
      Pipeline.terminate(pid)

      assert {:ok, {recordings, _meta}} = ExNVR.Recordings.list()
      recordings = Enum.sort_by(recordings, & &1.id, :asc)

      # The fixture is fed faster than realtime, so the wall clock trails the
      # media end date by far more than the 30 ms correction window; the
      # correction is therefore capped, shortening the second segment by
      # exactly 30 ms (6_000 -> 5_970). The first segment is anchored to the
      # wall clock and the last is flushed by end of stream, so neither is
      # corrected.
      assert durations_ms(recordings) == [6_000, 5_970, 2_950]

      # all the recordings belong to the same run
      assert [run] = ExNVR.Recordings.list_runs(%{device_id: device.id})
      assert Enum.map(recordings, & &1.run_id) |> Enum.uniq() == [run.id]

      for recording <- recordings, do: assert_valid_recording(device, recording, :h264)
    end

    test "drift bigger than 30 seconds starts a new run", %{device: device} do
      log =
        capture_log(fn ->
          # The stream is timestamped at 20 fps (50 ms/frame) and the first
          # segment is 6 s (120 frames). Jumping the clock forward 60 s from
          # frame 130 (~0.5 s into the second segment) makes the drift exceed
          # the 30 s threshold when that segment is finalized.
          pid =
            start_pipeline(device, @h264_fixtures,
              correct_timestamp: true,
              jump: {130, 60_000}
            )

          assert_end_of_stream(pid, :storage)
          Pipeline.terminate(pid)
        end)

      assert log =~ "Diff between segment end date and current date is more than 30 seconds"

      assert {:ok, {recordings, _meta}} = ExNVR.Recordings.list()
      assert [rec1, rec2, rec3] = Enum.sort_by(recordings, & &1.id, :asc)

      # the drifted segment keeps its media-based duration
      assert durations_ms([rec1, rec2, rec3]) == [6_000, 6_000, 2_950]

      # the run is closed and a new one starts at the wall clock date
      assert rec1.run_id == rec2.run_id
      assert rec1.run_id != rec3.run_id
      assert DateTime.diff(rec3.start_date, rec2.end_date) >= 30

      runs = ExNVR.Recordings.list_runs(%{device_id: device.id})
      assert length(runs) == 2
      assert Enum.all?(runs, &(not &1.active))

      for recording <- [rec1, rec2, rec3] do
        assert_valid_recording(device, recording, :h264)
      end
    end
  end

  describe "database failure" do
    setup :set_mimic_global

    test "segments stay on disk and the element keeps running", %{device: device} do
      # When the database insert fails, the run/recording is dropped and the
      # segment is orphaned on disk. This test pins the current behavior so
      # that a future fix is a deliberate change.
      stub(ExNVR.Recordings, :create, fn _device, _run, _recording, _copy_file? ->
        {:error, :database_unavailable}
      end)

      log =
        capture_log(fn ->
          pid = start_pipeline(device, @h264_fixtures)

          assert_end_of_stream(pid, :storage)
          Pipeline.terminate(pid)
        end)

      # all three segment closes failed and were logged; reaching end of
      # stream (above) proves the element survived every failed write
      assert Regex.scan(~r/Could not save recording/, log) |> length() == 3

      # no recordings nor runs are saved
      assert {:ok, {[], _meta}} = ExNVR.Recordings.list()
      assert [] = ExNVR.Recordings.list_runs(%{device_id: device.id})

      # the segments are still written to disk as complete, readable files
      files =
        Device.recording_dir(device)
        |> Path.join("**/*.mp4")
        |> Path.wildcard()

      assert length(files) == 3
      Enum.each(files, &assert_valid_mp4(&1, :h264))
    end
  end

  defp perform_test(device, fixture) do
    pid = start_pipeline(device, fixture)

    assert_end_of_stream(pid, :storage)
    Pipeline.terminate(pid)

    assert {:ok, {recordings, _meta}} = ExNVR.Recordings.list()
    assert length(recordings) == 3

    assert Enum.sort_by(recordings, & &1.id, :asc)
           |> Enum.map(&DateTime.diff(&1.end_date, &1.start_date)) == [6, 6, 2]

    for recording <- recordings do
      assert ExNVR.Recordings.recording_path(device, recording) |> File.exists?()
    end
  end

  defp perform_discontinuity_test(device, event) do
    chunks = chunk_file(@h264_fixtures)
    # cut the stream a quarter of the way in: the first part holds the
    # in-flight segment the discontinuity finalizes early, the rest is
    # recorded into a new run
    {first_part, second_part} = Enum.split(chunks, div(length(chunks), 4))

    # two events in a row: the first finalizes the open segment, the second
    # hits the element with no open segment and must be a no-op
    actions =
      buffer_actions(first_part) ++
        [event: {:output, event}, event: {:output, event}] ++
        buffer_actions(second_part) ++
        [end_of_stream: :output]

    pid = start_pipeline(device, @h264_fixtures, source: actions_source(actions))

    assert_end_of_stream(pid, :storage)
    Pipeline.terminate(pid)

    assert {:ok, {recordings, _meta}} = ExNVR.Recordings.list()
    assert [rec1, rec2, rec3] = Enum.sort_by(recordings, & &1.id, :asc)

    # the in-flight segment was cut short by the event
    assert [rec1_duration, rec2_duration, rec3_duration] = durations_ms(recordings)
    assert rec1_duration > 0
    assert rec1_duration < 6_000

    # recording resumes from the next keyframe into a new run
    assert rec2_duration == 6_000
    assert rec3_duration > 0

    assert rec1.run_id != rec2.run_id
    assert rec2.run_id == rec3.run_id

    runs = ExNVR.Recordings.list_runs(%{device_id: device.id})
    assert length(runs) == 2
    assert Enum.all?(runs, &(not &1.active))

    for recording <- [rec1, rec2, rec3] do
      assert_valid_recording(device, recording, :h264)
    end
  end

  defp start_pipeline(device, filename, opts \\ []) do
    parser =
      case Path.extname(filename) do
        ".h264" -> %Membrane.H264.Parser{generate_best_effort_timestamps: %{framerate: {20, 1}}}
        ".h265" -> %Membrane.H265.Parser{generate_best_effort_timestamps: %{framerate: {20, 1}}}
      end

    source = Keyword.get(opts, :source, %Source{output: chunk_file(filename)})

    spec = [
      child(:source, source)
      |> child(:parser, parser)
      |> child(:timestamper, %Timestamper{jump: Keyword.get(opts, :jump)})
      |> child(:storage, %Storage{
        device: device,
        target_segment_duration: Membrane.Time.seconds(4),
        correct_timestamp: Keyword.get(opts, :correct_timestamp, false)
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

  defp buffer_actions(chunks) do
    Enum.map(chunks, &{:buffer, {:output, %Membrane.Buffer{payload: &1}}})
  end

  # a source emitting the provided actions one by one without
  # automatically sending end of stream
  defp actions_source(actions) do
    generator = fn
      [], _size -> {[], []}
      [action | rest], _size -> {[action, redemand: :output], rest}
    end

    %Source{output: {actions, generator}}
  end

  defp durations_ms(recordings) do
    recordings
    |> Enum.sort_by(& &1.id, :asc)
    |> Enum.map(&DateTime.diff(&1.end_date, &1.start_date, :millisecond))
  end

  defp assert_valid_recording(device, recording, media) do
    path = ExNVR.Recordings.recording_path(device, recording)
    db_duration = DateTime.diff(recording.end_date, recording.start_date, :millisecond)
    assert_valid_mp4(path, media, db_duration)
  end

  # asserts the file on disk is a complete, readable mp4 with a non-empty
  # video track of the expected codec (and, when given, a movie duration
  # within 100 ms of the database recording's duration)
  defp assert_valid_mp4(path, media, expected_duration_ms \\ nil) do
    assert File.exists?(path)
    assert {:ok, reader} = ExMP4.Reader.new(path)

    track = ExMP4.Reader.track(reader, :video)
    assert track.media == media
    assert track.sample_count > 0

    if expected_duration_ms do
      assert_in_delta ExMP4.Reader.duration(reader, :millisecond), expected_duration_ms, 100
    end
  end
end
