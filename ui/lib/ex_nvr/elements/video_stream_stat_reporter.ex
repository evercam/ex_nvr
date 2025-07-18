defmodule ExNVR.Elements.VideoStreamStatReporter do
  @moduledoc """
  An element calculating realtime stats from a video stream (avg bitrate, avg fps, ..etc).
  """

  use Membrane.Sink

  require ExNVR.Utils

  alias Membrane.{H264, H265, Time}

  def_input_pad :input, accepted_format: any_of(H264, H265)

  def_options device_id: [
                spec: binary()
              ],
              stream: [
                spec: :high | :low,
                default: :high
              ]

  @info_event [:ex_nvr, :device, :stream, :info]
  @frame_event [:ex_nvr, :device, :stream, :frame]

  @impl true
  def handle_init(_ctx, opts) do
    state = Map.merge(init_state(), Map.from_struct(opts))
    {[], state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[start_timer: {:report_stats, Time.seconds(10)}], state}
  end

  @impl true
  def handle_event(:input, %Membrane.Event.Discontinuity{}, _ctx, state) do
    {[], Map.merge(state, init_state())}
  end

  @impl true
  def handle_event(:input, %ExNVR.Pipeline.Event.StreamClosed{}, _ctx, state) do
    {[], Map.merge(state, init_state())}
  end

  @impl true
  def handle_event(:input, event, ctx, state), do: super(:input, event, ctx, state)

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    codec =
      case stream_format do
        %H264{} -> :H264
        %H265{} -> :H265
      end

    state = %{
      state
      | resolution: {stream_format.width, stream_format.height},
        profile: stream_format.profile,
        codec: codec
    }

    :telemetry.execute(
      @info_event,
      %{value: 1},
      %{
        device_id: state.device_id,
        stream: state.stream,
        codec: codec,
        type: :video,
        profile: stream_format.profile,
        width: stream_format.width,
        height: stream_format.height
      }
    )

    {[], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    elapsed_time = max(Time.as_milliseconds(Time.monotonic_time() - state.start_time, :round), 1)
    total_bytes = state.total_bytes + IO.iodata_length(buffer.payload)
    total_frames = state.total_frames + 1

    state = %{
      state
      | total_bytes: total_bytes,
        total_frames: total_frames,
        avg_bitrate: div(total_bytes * 1_000 * 8, elapsed_time),
        avg_fps: total_frames * 1000 / elapsed_time
    }

    state =
      if ExNVR.Utils.keyframe(buffer) do
        %{
          state
          | avg_gop_size: calculate_avg_gop_size(state),
            gop_size: state.frames_since_last_keyframe,
            frames_since_last_keyframe: 1
        }
      else
        frames_since_last_keyframe = state.frames_since_last_keyframe + 1
        %{state | frames_since_last_keyframe: frames_since_last_keyframe}
      end

    :telemetry.execute(
      @frame_event,
      %{size: IO.iodata_length(buffer.payload), gop_size: state.gop_size},
      Map.take(state, [:device_id, :stream])
    )

    {[], state}
  end

  @impl true
  def handle_tick(:report_stats, _ctx, state) do
    stats = %ExNVR.Pipeline.Track.Stat{
      width: state.resolution && elem(state.resolution, 0),
      height: state.resolution && elem(state.resolution, 1),
      profile: state.profile,
      recv_bytes: state.total_bytes,
      total_frames: state.total_frames,
      gop_size: state.gop_size
    }

    {[notify_parent: {:stats, stats}], state}
  end

  defp init_state do
    %{
      start_time: Time.monotonic_time(),
      codec: nil,
      resolution: nil,
      profile: nil,
      elapsed_time: 0,
      total_bytes: 0,
      total_frames: 0,
      frames_since_last_keyframe: 0,
      avg_bitrate: 0,
      avg_fps: 0,
      avg_gop_size: nil,
      gop_size: 0
    }
  end

  defp calculate_avg_gop_size(%{avg_gop_size: nil}), do: 0
  defp calculate_avg_gop_size(%{avg_gop_size: 0} = state), do: state.frames_since_last_keyframe

  defp calculate_avg_gop_size(state) do
    (state.avg_gop_size + state.frames_since_last_keyframe) / 2
  end
end
