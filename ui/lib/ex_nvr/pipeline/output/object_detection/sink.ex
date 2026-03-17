defmodule ExNVR.Pipeline.Output.ObjectDetection.Sink do
  @moduledoc false

  use Membrane.Sink

  alias Membrane.RawVideo

  def_input_pad :input, accepted_format: %RawVideo{}

  @impl true
  def handle_init(_ctx, _options) do
    state = %{
      width: nil,
      height: nil,
      frames: 0,
      started_at_ms: System.monotonic_time(:millisecond)
    }

    {[], state}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    state = %{state | width: stream_format.width, height: stream_format.height}
    {[], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    frame_count = state.frames + 1
    elapsed_ms = System.monotonic_time(:millisecond) - state.started_at_ms
    fps = if elapsed_ms > 0, do: frame_count * 1000 / elapsed_ms, else: 0.0

    detections = Map.get(buffer.metadata, :detections, [])
    tracks = Map.get(buffer.metadata, :tracks, [])
    frame_width = Map.get(buffer.metadata, :frame_width, state.width)
    frame_height = Map.get(buffer.metadata, :frame_height, state.height)

    payload = %{
      fps: Float.round(fps, 2),
      frame_width: frame_width,
      frame_height: frame_height,
      detections:
        Enum.map(detections, fn d ->
          %{
            xmin: d.xmin,
            ymin: d.ymin,
            xmax: d.xmax,
            ymax: d.ymax,
            score: d.score,
            class_id: d.class_id,
            class_name: d.class_name
          }
        end),
      tracks:
        Enum.map(tracks, fn t ->
          %{
            x: t.x,
            y: t.y,
            width: t.width,
            height: t.height,
            id: t.id,
            class_id: Map.get(t, :class_id),
            class_name: Map.get(t, :class_name, "unknown"),
            score: Map.get(t, :score)
          }
        end)
    }

    {[notify_parent: {:tracking_data, payload}], %{state | frames: frame_count}}
  end
end
