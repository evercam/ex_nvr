defmodule ExNVR.Elements.Segmenter do
  @moduledoc """
  Element responsible for splitting the stream into segments of fixed duration.

  Once the duration of a segment reach the `segment_duration` specified, a new notification is
  sent to the parent to inform it of the start of a new segment.

  The parent should link the `Pad.ref(:output, segment_ref)` to start receiving the data of the new segment.

  Note that an `end_of_stream` action is sent on the old `Pad.ref(:output, segment_ref)`
  """

  use Membrane.Filter

  require Membrane.Logger

  alias ExNVR.Elements.Segmenter.Segment
  alias Membrane.{Buffer, Event, H264}

  def_options segment_duration: [
                spec: non_neg_integer(),
                default: 60,
                description: """
                The duration of each segment in seconds.
                A segment may not have the exact duration specified here, since each
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
        target_segment_duration: Membrane.Time.seconds(options.segment_duration)
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
        %Buffer{metadata: %{h264: %{key_frame?: true}}} = buf,
        _ctx,
        %{start_time: nil} = state
      ) do
    state = %{
      state
      | start_time: Membrane.Time.vm_time(),
        buffer: [buf],
        last_buffer_pts: buf.pts
    }

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
    {[], %{state | buffer: [buffer | state.buffer]}}
  end

  defp handle_buffer(state, %Buffer{metadata: %{h264: %{key_frame?: true}}} = buffer)
       when state.current_segment_duration >= state.target_segment_duration do
    completed_segment_action = completed_segment_action(state)
    pad_ref = state.start_time

    state = %{
      state
      | start_time: state.start_time + state.current_segment_duration,
        current_segment_duration: 0,
        buffer?: true,
        buffer: [buffer]
    }

    {[
       end_of_stream: Pad.ref(:output, pad_ref),
       notify_parent: {:new_media_segment, state.start_time}
     ] ++ completed_segment_action, state}
  end

  defp handle_buffer(state, buffer),
    do: {[buffer: {Pad.ref(:output, state.start_time), buffer}], state}

  defp do_handle_end_of_stream(%{start_time: nil} = state) do
    {[], state}
  end

  defp do_handle_end_of_stream(state) do
    {[end_of_stream: Pad.ref(:output, state.start_time)] ++ completed_segment_action(state, true),
     Map.merge(state, init_state())}
  end

  defp update_segment_duration(state, %Buffer{pts: pts} = buf) do
    frame_duration = pts - state.last_buffer_pts

    %{
      state
      | current_segment_duration: state.current_segment_duration + frame_duration,
        last_buffer_pts: buf.pts
    }
  end

  defp init_state() do
    %{
      current_segment_duration: 0,
      last_buffer_pts: nil,
      buffer: [],
      buffer?: true,
      start_time: nil
    }
  end

  defp completed_segment_action(state, discontinuity \\ false) do
    segment = %Segment{
      start_date: Membrane.Time.to_datetime(state.start_time),
      end_date: Membrane.Time.to_datetime(state.start_time + state.current_segment_duration),
      duration: Membrane.Time.as_seconds(state.current_segment_duration)
    }

    [notify_parent: {:completed_segment, {state.start_time, segment, discontinuity}}]
  end
end
