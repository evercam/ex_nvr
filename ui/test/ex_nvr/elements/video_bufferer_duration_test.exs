defmodule ExNVR.Elements.VideoBuffererDurationTest do
  @moduledoc """
  Tests that verify the VideoBufferer holds the correct number of frames
  for seconds-based eviction and that flushed output has the expected
  duration. Uses both direct callback math and a real Membrane pipeline
  with fixture data verified by ExMP4.
  """

  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias ExNVR.Elements.VideoBufferer
  alias ExNVR.Pipeline.Output.Storage
  alias ExNVR.Triggers.Targets.TriggerRecording
  alias Membrane.Testing.{Pipeline, Source}

  @moduletag :tmp_dir

  @h264_fixture Path.expand("../../fixtures/video-30-10s.h264", __DIR__)

  # --- Direct callback tests: verify frame counts via math ---

  @ctx %{}

  defp init(opts) do
    options = %VideoBufferer{
      topic: Keyword.get(opts, :topic, "test-topic"),
      limit: Keyword.get(opts, :limit, {:keyframes, 3}),
      event_timeout: Keyword.get(opts, :event_timeout, 30_000)
    }

    {[], state} = VideoBufferer.handle_init(@ctx, options)
    state
  end

  defp h264_buffer(opts) do
    %Membrane.Buffer{
      payload: Keyword.get(opts, :payload, :crypto.strong_rand_bytes(100)),
      pts: Keyword.get(opts, :pts, nil),
      metadata: %{h264: %{key_frame?: Keyword.get(opts, :key_frame?, false)}}
    }
  end

  defp send_buffers(state, buffers) do
    Enum.reduce(buffers, {[], state}, fn buffer, {_prev_actions, state} ->
      VideoBufferer.handle_buffer(:input, buffer, @ctx, state)
    end)
  end

  defp send_event(state) do
    VideoBufferer.handle_info({:event, "recording_triggered"}, @ctx, state)
  end

  defp output_buffers(actions) do
    case Keyword.get(actions, :buffer) do
      {:output, buffers} when is_list(buffers) -> buffers
      {:output, buffer} -> [buffer]
      nil -> []
    end
  end

  # Generate frames at a given fps with keyframes every `gop` frames.
  defp generate_frames(count, fps, gop) do
    frame_duration = div(Membrane.Time.seconds(1), fps)

    for i <- 0..(count - 1) do
      h264_buffer(
        key_frame?: rem(i, gop) == 0,
        pts: i * frame_duration,
        payload: :crypto.strong_rand_bytes(500)
      )
    end
  end

  describe "seconds eviction frame count at realistic frame rates" do
    test "30fps, 5s buffer holds ~150 frames" do
      state = init(limit: {:seconds, 5})
      fps = 30
      gop = 30
      # 10 seconds of data, buffer should keep ~5s
      frames = generate_frames(300, fps, gop)

      {_actions, state} = send_buffers(state, frames)

      count = :queue.len(state.buffer)
      # At 30fps, 5 seconds = 150 frames. Allow ±fps for rounding.
      assert count >= fps * 5 - fps,
             "Expected at least #{fps * 5 - fps} frames, got #{count}"

      assert count <= fps * 5 + fps + 1,
             "Expected at most #{fps * 5 + fps + 1} frames, got #{count}"
    end

    test "20fps, 10s buffer holds ~200 frames" do
      state = init(limit: {:seconds, 10})
      fps = 20
      gop = 20
      # 20 seconds of data
      frames = generate_frames(400, fps, gop)

      {_actions, state} = send_buffers(state, frames)

      count = :queue.len(state.buffer)

      assert count >= fps * 10 - fps,
             "Expected at least #{fps * 10 - fps} frames, got #{count}"

      assert count <= fps * 10 + fps + 1,
             "Expected at most #{fps * 10 + fps + 1} frames, got #{count}"
    end

    test "25fps, 3s buffer holds ~75 frames" do
      state = init(limit: {:seconds, 3})
      fps = 25
      gop = 25
      # 10 seconds of data
      frames = generate_frames(250, fps, gop)

      {_actions, state} = send_buffers(state, frames)

      count = :queue.len(state.buffer)

      assert count >= fps * 3 - fps,
             "Expected at least #{fps * 3 - fps} frames, got #{count}"

      assert count <= fps * 3 + fps + 1,
             "Expected at most #{fps * 3 + fps + 1} frames, got #{count}"
    end
  end

  describe "flush duration matches buffer config" do
    test "flushed frames span approximately the buffer duration" do
      state = init(limit: {:seconds, 5})
      fps = 30
      gop = 30
      frames = generate_frames(300, fps, gop)

      {_actions, state} = send_buffers(state, frames)
      {actions, _state} = send_event(state)

      flushed = output_buffers(actions)
      assert flushed != [], "Expected flushed frames, got none"

      first_pts = hd(flushed).pts
      last_pts = List.last(flushed).pts
      span_ms = Membrane.Time.as_milliseconds(last_pts - first_pts, :round)

      # flush_from_keyframe returns from the FIRST keyframe to end of buffer.
      # The full pre-roll should span approximately the buffer limit.
      assert span_ms >= 4000,
             "Flushed span #{span_ms}ms should be close to buffer limit (5s)"

      assert span_ms <= 6000,
             "Flushed span #{span_ms}ms should not exceed buffer limit by much"
    end

    test "frame count in flushed output matches framerate math" do
      state = init(limit: {:seconds, 5})
      fps = 30
      gop = 30
      frames = generate_frames(300, fps, gop)

      {_actions, state} = send_buffers(state, frames)
      {actions, _state} = send_event(state)

      flushed = output_buffers(actions)
      first_pts = hd(flushed).pts
      last_pts = List.last(flushed).pts
      span_s = Membrane.Time.as_milliseconds(last_pts - first_pts, :round) / 1000

      expected_frames = round(span_s * fps) + 1
      actual_frames = length(flushed)

      assert abs(actual_frames - expected_frames) <= 2,
             "Expected ~#{expected_frames} frames for #{span_s}s at #{fps}fps, got #{actual_frames}"
    end
  end

  # --- Pipeline test: verify output recording duration with ExMP4 ---

  defmodule Timestamper do
    @moduledoc false
    use Membrane.Filter

    def_input_pad :input, accepted_format: _any
    def_output_pad :output, accepted_format: _any

    @impl true
    def handle_init(_ctx, _opts), do: {[], nil}

    @impl true
    def handle_buffer(:input, buffer, _ctx, state) do
      metadata =
        buffer.metadata
        |> update_nalus_metadata()
        |> Map.put(:timestamp, System.os_time(:millisecond))

      buffer = %{buffer | metadata: metadata}
      {[buffer: {:output, buffer}], state}
    end

    defp update_nalus_metadata(%{h264: %{nalus: nalus}} = metadata) do
      nalus = Enum.map(nalus, & &1.metadata.h264.type)
      put_in(metadata, [:h264, :nalus], nalus)
    end

    defp update_nalus_metadata(metadata), do: metadata
  end

  describe "pipeline output verified by ExMP4" do
    setup %{tmp_dir: tmp_dir} do
      device =
        camera_device_fixture(tmp_dir, %{
          storage_config: %{recording_mode: :on_event}
        })

      %{device: device, tmp_dir: tmp_dir}
    end

    @tag timeout: 30_000
    test "event produces recording with duration matching buffer + forwarded frames",
         %{device: device} do
      topic = TriggerRecording.topic("ffprobe-test")

      # video-30-10s.h264 parsed at 20fps → ~200 frames over 10s
      # Buffer limit: 3s → pre-roll captures ~3s
      # Event fires immediately → buffer flush + remaining frames forwarded
      pid = start_h264_pipeline(device, topic, limit: {:seconds, 3}, event_timeout: 30_000)

      # Fire event — flushes buffer and starts forwarding remaining frames
      Phoenix.PubSub.broadcast(ExNVR.PubSub, topic, {:event, "recording_triggered"})

      assert_end_of_stream(pid, :storage, :input, 15_000)
      Pipeline.terminate(pid)

      assert {:ok, {recordings, _meta}} = ExNVR.Recordings.list()
      assert recordings != []

      total_duration =
        recordings
        |> Enum.map(fn recording ->
          path = ExNVR.Recordings.recording_path(device, recording)
          mp4_duration(path)
        end)
        |> Enum.sum()

      # Event fires early so most of the file flows through.
      # At 20fps over ~10s source, total should be well above 3s.
      assert total_duration > 3.0,
             "Total recording duration #{total_duration}s is too short, expected > 3s"
    end

    @tag timeout: 30_000
    test "frame count in recording matches framerate expectation", %{device: device} do
      topic = TriggerRecording.topic("framecount-test")

      pid = start_h264_pipeline(device, topic, limit: {:seconds, 3}, event_timeout: 30_000)

      Phoenix.PubSub.broadcast(ExNVR.PubSub, topic, {:event, "recording_triggered"})

      assert_end_of_stream(pid, :storage, :input, 15_000)
      Pipeline.terminate(pid)

      assert {:ok, {recordings, _meta}} = ExNVR.Recordings.list()
      assert recordings != []

      total_frames =
        recordings
        |> Enum.map(fn recording ->
          path = ExNVR.Recordings.recording_path(device, recording)
          mp4_frame_count(path)
        end)
        |> Enum.sum()

      # Parser generates timestamps at 20fps. The source has ~200 frames.
      # Event fires early, so most pass through. 50 is a conservative floor.
      assert total_frames > 50,
             "Total frames #{total_frames} is too low. At 20fps, expected significantly more."

      # Verify math: total_frames / 20fps should give approximate duration
      calculated_duration = total_frames / 20

      assert calculated_duration > 2.0,
             "Calculated duration #{calculated_duration}s (#{total_frames} frames / 20fps) too short"
    end
  end

  defp start_h264_pipeline(device, topic, opts) do
    limit = Keyword.get(opts, :limit, {:seconds, 3})
    event_timeout = Keyword.get(opts, :event_timeout, 30_000)

    spec = [
      child(:source, %Source{output: chunk_file(@h264_fixture)})
      |> child(:parser, %Membrane.H264.Parser{
        generate_best_effort_timestamps: %{framerate: {20, 1}}
      })
      |> child(:timestamper, Timestamper)
      |> child(:video_bufferer, %VideoBufferer{
        topic: topic,
        limit: limit,
        event_timeout: event_timeout
      })
      |> child(:storage, %Storage{
        device: device,
        target_segment_duration: Membrane.Time.seconds(10),
        correct_timestamp: true
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

  defp mp4_duration(path) do
    {:ok, reader} = ExMP4.Reader.new(path)
    duration_ms = ExMP4.Reader.duration(reader, :millisecond)
    ExMP4.Reader.close(reader)
    duration_ms / 1000
  end

  defp mp4_frame_count(path) do
    {:ok, reader} = ExMP4.Reader.new(path)
    track = ExMP4.Reader.track(reader, :video)
    count = track.sample_count
    ExMP4.Reader.close(reader)
    count
  end
end
