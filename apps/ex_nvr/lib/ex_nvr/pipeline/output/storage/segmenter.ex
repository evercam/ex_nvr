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
  alias Membrane.{Buffer, Event, H264, Time}

  @time_error Time.milliseconds(30)

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
    demand_unit: :buffers,
    demand_mode: :auto,
    accepted_format: %H264{alignment: :au},
    availability: :always

  def_output_pad :output,
    demand_mode: :auto,
    accepted_format: %H264{alignment: :au},
    availability: :on_request

  @impl true
  def handle_init(_ctx, options) do
    state =
      Map.merge(init_state(), %{
        stream_format: nil,
        target_duration: Time.seconds(options.target_duration),
        correct_timestamp: options.correct_timestamp
      })

    {[], state}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    {[], %{state | stream_format: stream_format}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, ref), _ctx, %{start_time: ref} = state) do
    buffered_actions =
      state.buffer
      |> Enum.reverse()
      |> Enum.map(&{:buffer, {Pad.ref(:output, ref), &1}})

    {[stream_format: {Pad.ref(:output, ref), state.stream_format}] ++ buffered_actions,
     %{state | buffer?: false, buffer: []}}
  end

  @impl true
  def handle_process(:input, buffer, _ctx, %{start_time: nil} = state)
      when not Utils.keyframe(buffer) do
    # ignore, we need to start recording from a keyframe
    {[], state}
  end

  @impl true
  def handle_process(:input, buffer, _ctx, %{start_time: nil} = state)
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

    {[notify_parent: {:new_media_segment, state.start_time}], state}
  end

  @impl true
  def handle_process(:input, %Buffer{} = buf, _ctx, state) do
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
      state = finalize_segment(state, state.correct_timestamp)

      actions =
        [end_of_stream: Pad.ref(:output, state.start_time)] ++ completed_segment_action(state)

      start_time = Segment.end_date(state.segment)

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

      {[notify_parent: {:new_media_segment, start_time}] ++ actions, state}
    else
      state = update_segment_size(state, buffer)
      {[buffer: {Pad.ref(:output, state.start_time), buffer}], state}
    end
  end

  defp do_handle_end_of_stream(%{start_time: nil} = state) do
    {[], state}
  end

  defp do_handle_end_of_stream(state) do
    state = finalize_segment(state)

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

  defp finalize_segment(%{segment: segment} = state, correct_timestamp \\ false) do
    end_date = Time.os_time()
    monotonic_end_date = Time.monotonic_time()

    segment =
      segment
      |> maybe_correct_timestamp(correct_timestamp, state, end_date)
      |> Segment.with_realtime_duration(monotonic_end_date - state.monotonic_start_time)
      |> then(&Segment.with_wall_clock_duration(&1, end_date - &1.start_date))

    %{state | segment: %{segment | wallclock_end_date: end_date}}
  end

  defp maybe_correct_timestamp(segment, false, %{first_segment?: false}, _end_date), do: segment

  defp maybe_correct_timestamp(segment, true, %{first_segment?: false}, end_date) do
    # clap the time diff between -@time_error and @time_error
    time_diff = end_date - Segment.end_date(segment)
    diff = time_diff |> max(-@time_error) |> min(@time_error)
    Segment.add_duration(segment, diff)
  end

  defp maybe_correct_timestamp(segment, _correct_timestamp, _state, end_date),
    do: %{segment | start_date: end_date - Segment.duration(segment), end_date: end_date}

  defp completed_segment_action(state, discontinuity \\ false) do
    [notify_parent: {:completed_segment, {state.start_time, state.segment, discontinuity}}]
  end
end
