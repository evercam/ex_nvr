defmodule ExNVR.Elements.Segmenter do
  @moduledoc """
  Element responsible for splitting the stream into segments of fixed duration.

  Once the duration of a segment reach the provided `target_duration`, a new notification is
  emitted to the parent to inform it of the start of a new segment.

  The parent should link the `Pad.ref(:output, segment_ref)` to start receiving the data of the new segment.

  Note that an `end_of_stream` action is sent on the old `Pad.ref(:output, segment_ref)`
  """

  use Membrane.Filter

  require Membrane.Logger

  alias ExNVR.Elements.Segmenter.Segment
  alias Membrane.{Buffer, Event, H264}

  def_options target_duration: [
                spec: non_neg_integer(),
                default: 60,
                description: """
                The target duration of each segment in seconds.

                A segment may not have the exact duration provided here, since each
                segment must start from a keyframe. The real segment duration may be
                slightly bigger
                """
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
        target_duration: Membrane.Time.seconds(options.target_duration)
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
  def handle_process(
        :input,
        %Buffer{metadata: %{h264: %{key_frame?: false}}},
        _ctx,
        %{start_time: nil} = state
      ) do
    # ignore, we need to start recording from a keyframe
    {[], state}
  end

  @impl true
  def handle_process(
        :input,
        %Buffer{metadata: %{h264: %{key_frame?: true}}} = buffer,
        _ctx,
        %{start_time: nil} = state
      ) do
    # we chose the os_time instead of vm_time since the
    # VM will not adjust the time when the the system is suspended
    # check https://erlangforums.com/t/why-is-there-a-discrepancy-between-values-returned-by-os-system-time-1-and-erlang-system-time-1/2050/2
    start_time = Membrane.Time.os_time()

    state =
      %{
        state
        | start_time: start_time,
          segment: Segment.new(start_time),
          buffer: [buffer],
          last_buffer_dts: Buffer.get_dts_or_pts(buffer)
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
    key_frame? = buffer.metadata.h264.key_frame?

    if key_frame? and Segment.duration(state.segment) >= state.target_duration do
      actions =
        [end_of_stream: Pad.ref(:output, state.start_time)] ++ completed_segment_action(state)

      start_time = state.start_time + Segment.duration(state.segment)

      state =
        %{
          state
          | start_time: start_time,
            segment: Segment.new(start_time),
            buffer?: true,
            buffer: [buffer]
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
      parameter_sets: []
    }
  end

  defp completed_segment_action(state, discontinuity \\ false) do
    [notify_parent: {:completed_segment, {state.start_time, state.segment, discontinuity}}]
  end
end
