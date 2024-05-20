defmodule ExNVR.Elements.VideoStreamStatReporter do
  @moduledoc """
  An element calculating realtime stats from a video stream (avg bitrate, avg fps, ..etc).

  The element reports the stats to its parent at a regular interval (e.g. each 10 seconds)
  """

  use Membrane.Filter

  require ExNVR.Utils

  alias Membrane.{H264, H265}

  def_input_pad :input, accepted_format: any_of(H264, H265)

  def_output_pad :output, accepted_format: any_of(H264, H265)

  def_options report_interval: [
                spec: Membrane.Time.t(),
                description: """
                Send a notification to the parent containing the calulcated stats at
                a regular interval spcified by this option.
                """,
                default: Membrane.Time.seconds(10)
              ]

  @impl true
  def handle_init(_ctx, opts) do
    {[], Map.put(init_state(), :report_interval, opts.report_interval)}
  end

  @impl true
  def handle_setup(_ctx, state) do
    {[start_timer: {:report_stats, state.report_interval}], state}
  end

  @impl true
  def handle_event(:input, %Membrane.Event.Discontinuity{} = ev, _ctx, state) do
    {[forward: {:output, ev}], Map.merge(state, init_state())}
  end

  @impl true
  def handle_event(:input, event, ctx, state), do: super(:input, event, ctx, state)

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    state = %{
      state
      | resolution: {stream_format.width, stream_format.height},
        profile: stream_format.profile
    }

    {[stream_format: {:output, stream_format}], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    state = %{
      state
      | total_bytes: state.total_bytes + byte_size(buffer.payload),
        total_frames: state.total_frames + 1
    }

    state =
      if ExNVR.Utils.keyframe(buffer) do
        %{state | avg_gop_size: calculate_avg_gop_size(state), frames_since_last_keyframe: 1}
      else
        frames_since_last_keyframe = state.frames_since_last_keyframe + 1
        %{state | frames_since_last_keyframe: frames_since_last_keyframe}
      end

    {[buffer: {:output, buffer}], state}
  end

  @impl true
  def handle_tick(:report_stats, _ctx, state) do
    elapsed_time = state.elapsed_time + Membrane.Time.as_seconds(state.report_interval, :round)

    stats =
      state
      |> Map.take([:resolution, :profile, :avg_gop_size])
      |> Map.merge(%{
        avg_fps: state.total_frames / elapsed_time,
        avg_bitrate: div(state.total_bytes * 8, elapsed_time)
      })

    {[notify_parent: {:stats, stats}], %{state | elapsed_time: elapsed_time}}
  end

  defp init_state() do
    %{
      resolution: nil,
      profile: nil,
      elapsed_time: 0,
      total_bytes: 0,
      total_frames: 0,
      frames_since_last_keyframe: 0,
      avg_gop_size: nil
    }
  end

  defp calculate_avg_gop_size(%{avg_gop_size: nil}), do: 0
  defp calculate_avg_gop_size(%{avg_gop_size: 0} = state), do: state.frames_since_last_keyframe

  defp calculate_avg_gop_size(state) do
    (state.avg_gop_size + state.frames_since_last_keyframe) / 2
  end
end
