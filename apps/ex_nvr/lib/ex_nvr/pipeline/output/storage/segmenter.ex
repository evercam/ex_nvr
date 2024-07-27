defmodule ExNVR.Pipeline.Output.Storage.Segmenter do
  @moduledoc """
  Element responsible for splitting the stream into segments of fixed duration.

  Once the duration of a segment reach the provided `target_duration`, a new notification is
  emitted to the parent to inform it of the start of a new segment.

  The parent should link the `Pad.ref(:output, segment_ref)` to start receiving the data of the new segment.

  Note that an `end_of_stream` action is sent on the old `Pad.ref(:output, segment_ref)`
  """

  use Membrane.Filter

  require Membrane.Logger
  require ExNVR.Utils

  alias __MODULE__.Segment
  alias ExNVR.Utils
  alias Membrane.{Buffer, Event, H264, H265, Time}

  @time_error Time.milliseconds(30)
  @time_drift_threshold Time.seconds(30)
  @jitter_buffer_delay Time.milliseconds(200)

  def_options target_duration: [
                spec: non_neg_integer(),
                default: 60,
                description: """
                The target duration of each segment in seconds.

                A segment may not have the exact duration provided here, since each
                segment must start from a keyframe. The real segment duration may be
                slightly bigger
                """
              ],
              correct_timestamp: [
                spec: boolean(),
                default: false,
                description: "See `ExNVR.Pipeline.Output.Storage`"
              ]

  def_input_pad :input,
    flow_control: :auto,
    accepted_format:
      any_of(
        %H264{alignment: :au},
        %H265{alignment: :au}
      ),
    availability: :always

  def_output_pad :output,
    flow_control: :auto,
    accepted_format:
      any_of(
        %H264{alignment: :au},
        %H265{alignment: :au}
      ),
    availability: :on_request

  @impl true
  def handle_init(_ctx, options) do
    state =
      Map.merge(init_state(), %{
        stream_format: nil,
        target_duration: Time.seconds(options.target_duration),
        correct_timestamp: options.correct_timestamp,
        codec: nil
      })

    {[], state}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    codec =
      case stream_format do
        %H264{} -> :H264
        %H265{} -> :H265
      end

    {[], %{state | stream_format: stream_format, codec: codec}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, ref) = pad, _ctx, %{start_time: ref} = state) do
    buffered_actions =
      state.buffer
      |> Enum.reverse()
      |> Enum.map(&{:buffer, {pad, &1}})

    {[stream_format: {pad, state.stream_format}] ++ buffered_actions,
     %{state | buffer?: false, buffer: []}}
  end

  @impl true
  def handle_pad_removed(Pad.ref(:output, ref), _ctx, %{start_time: ref}) do
    {[], init_state()}
  end

  @impl true
  def handle_pad_removed(_pad, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, %{start_time: nil} = state)
      when not Utils.keyframe(buffer) do
    # ignore, we need to start recording from a keyframe
    {[], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, %{start_time: nil} = state)
      when Utils.keyframe(buffer) do
    # we chose the os_time instead of vm_time since the
    # VM will not adjust the time when the the system is suspended
    # check https://erlangforums.com/t/why-is-there-a-discrepancy-between-values-returned-by-os-system-time-1-and-erlang-system-time-1/2050/2
    start_time = Time.os_time()

    state =
      %{
        state
        | start_time: start_time,
          segment: Segment.new(start_time),
          buffer: [buffer],
          last_buffer_dts: Buffer.get_dts_or_pts(buffer),
          monotonic_start_time: System.monotonic_time()
      }
      |> update_segment_size(buffer)

    {[notify_parent: {:new_media_segment, state.start_time, state.codec}], state}
  end

  @impl true
  def handle_buffer(:input, %Buffer{} = buf, _ctx, state) do
    state
    |> update_segment_duration(buf)
    |> handle_buffer(buf)
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    do_handle_end_of_stream(state)
  end

  @impl true
  def handle_event(:input, %Event.Discontinuity{}, _ctx, state) do
    do_handle_end_of_stream(state)
  end

  defp handle_buffer(%{buffer?: true} = state, buffer) do
    state = update_segment_size(state, buffer)
    {[], %{state | buffer: [buffer | state.buffer]}}
  end

  defp handle_buffer(state, %Buffer{} = buffer) do
    if Utils.keyframe(buffer) and Segment.duration(state.segment) >= state.target_duration do
      {state, discontinuity} = finalize_segment(state, state.correct_timestamp)

      actions =
        [end_of_stream: Pad.ref(:output, state.start_time)] ++
          completed_segment_action(state, discontinuity)

      start_time =
        if discontinuity,
          do: state.segment.wallclock_end_date,
          else: Segment.end_date(state.segment)

      state =
        %{
          state
          | start_time: start_time,
            segment: Segment.new(start_time),
            buffer?: true,
            buffer: [buffer],
            monotonic_start_time: System.monotonic_time(),
            first_segment?: false
        }
        |> update_segment_size(buffer)

      {[notify_parent: {:new_media_segment, start_time, state.codec}] ++ actions, state}
    else
      state = update_segment_size(state, buffer)
      {[buffer: {Pad.ref(:output, state.start_time), buffer}], state}
    end
  end

  defp do_handle_end_of_stream(%{start_time: nil} = state) do
    {[], state}
  end

  defp do_handle_end_of_stream(state) do
    {state, _discontinuity} = finalize_segment(state, false)

    {[end_of_stream: Pad.ref(:output, state.start_time)] ++ completed_segment_action(state, true),
     Map.merge(state, init_state())}
  end

  defp update_segment_duration(state, %Buffer{} = buf) do
    dts = Buffer.get_dts_or_pts(buf)
    frame_duration = dts - state.last_buffer_dts

    %{
      state
      | segment: Segment.add_duration(state.segment, frame_duration),
        last_buffer_dts: dts
    }
  end

  defp update_segment_size(state, %Buffer{} = buf) do
    %{state | segment: Segment.add_size(state.segment, byte_size(buf.payload))}
  end

  defp init_state() do
    %{
      segment: nil,
      last_buffer_dts: nil,
      buffer: [],
      buffer?: true,
      start_time: nil,
      monotonic_start_time: 0,
      first_segment?: true
    }
  end

  defp finalize_segment(%{segment: segment} = state, correct_timestamp) do
    end_date = Time.os_time() - @jitter_buffer_delay
    monotonic_duration = Time.monotonic_time() - state.monotonic_start_time

    {segment, discontinuity?} =
      maybe_correct_timestamp(segment, correct_timestamp, state, end_date)

    segment =
      segment
      |> Segment.with_realtime_duration(monotonic_duration)
      |> Segment.with_wall_clock_duration(end_date - segment.start_date)
      |> then(&%{&1 | wallclock_end_date: end_date})

    {%{state | segment: segment}, discontinuity?}
  end

  defp maybe_correct_timestamp(segment, false, %{first_segment?: false}, _end_date),
    do: {segment, false}

  defp maybe_correct_timestamp(segment, true, %{first_segment?: false}, end_date) do
    # clap the time diff between -@time_error and @time_error
    time_diff = end_date - Segment.end_date(segment)

    if abs(time_diff) >= @time_drift_threshold do
      Membrane.Logger.warning("""
      Diff between segment end date and current date is more than #{Time.as_seconds(@time_drift_threshold, :round)} seconds
      diff: #{Time.as_microseconds(time_diff, :round)}
      """)

      {segment, true}
    else
      diff = time_diff |> max(-@time_error) |> min(@time_error)
      {Segment.add_duration(segment, diff), false}
    end
  end

  defp maybe_correct_timestamp(segment, _correct_timestamp, _state, end_date) do
    start_date = end_date - Segment.duration(segment)
    {%{segment | start_date: start_date, end_date: end_date}, false}
  end

  defp completed_segment_action(state, discontinuity \\ false) do
    [notify_parent: {:completed_segment, {state.start_time, state.segment, discontinuity}}]
  end
end
