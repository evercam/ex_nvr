defmodule ExNVR.Elements.VideoBuffererPipelineTest do
  @moduledoc """
  Integration tests for VideoBufferer in a real Membrane pipeline.

  Verifies that the buffering → event → forwarding → timeout → discontinuity
  flow works end-to-end with actual H264 data and the Storage sink.
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

  @h264_fixture "../../fixtures/video-30-10s.h264" |> Path.expand(__DIR__)

  # Inline timestamper — adds :timestamp metadata that Storage requires,
  # and flattens nalus metadata. Same as in storage_pipeline_test.
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

  setup %{tmp_dir: tmp_dir} do
    device =
      camera_device_fixture(tmp_dir, %{
        storage_config: %{recording_mode: :on_event}
      })

    %{device: device}
  end

  test "no event — frames are buffered, no recordings created", %{device: device} do
    topic = TriggerRecording.topic("no-event-test")

    pid = start_pipeline(device, topic)

    assert_end_of_stream(pid, :storage, :input, 10_000)
    Pipeline.terminate(pid)

    assert {:ok, {[], _meta}} = ExNVR.Recordings.list()
  end

  test "event triggers buffer flush and recordings are created", %{device: device} do
    topic = TriggerRecording.topic("event-test")

    pid = start_pipeline(device, topic)

    # Broadcast event — VideoBufferer flushes buffer and starts forwarding.
    # The pipeline is already set up and data is flowing by the time
    # start_pipeline returns, so the bufferer has frames to flush.
    Phoenix.PubSub.broadcast(ExNVR.PubSub, topic, {:event, "recording_triggered"})

    assert_end_of_stream(pid, :storage, :input, 10_000)
    Pipeline.terminate(pid)

    assert {:ok, {recordings, _meta}} = ExNVR.Recordings.list()
    assert recordings != []
  end

  test "event timeout sends discontinuity and creates a segment boundary", %{device: device} do
    topic = TriggerRecording.topic("timeout-test")

    # Short timeout so we can observe the discontinuity effect
    pid = start_pipeline(device, topic, event_timeout: 200)

    # Start forwarding
    Phoenix.PubSub.broadcast(ExNVR.PubSub, topic, {:event, "recording_triggered"})

    # Let some frames through, then let the timeout fire.
    # The timeout sends Discontinuity → Storage closes the current segment.
    # Then end_of_stream arrives → Storage closes again (no-op if no data).
    assert_end_of_stream(pid, :storage, :input, 10_000)
    Pipeline.terminate(pid)

    assert {:ok, {recordings, _meta}} = ExNVR.Recordings.list()
    assert recordings != []
  end

  defp start_pipeline(device, topic, opts \\ []) do
    limit = Keyword.get(opts, :limit, {:keyframes, 3})
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
        target_segment_duration: Membrane.Time.seconds(4),
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
end
