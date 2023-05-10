defmodule ExNVR.Segmenter do
  @moduledoc """
  Element that marks the beginning of a new segment.

  Once the duration of a segment reach the `segment_duration` specified, a new notification is
  sent to the parent to inform it of the start of a new segment.

  The parent should link the `Pad.ref(:output, segment_ref)` to start receiving the data of the new segment.

  Note that an `end_of_stream` action is sent on the old `Pad.ref(:output, segment_ref)`
  """

  use Membrane.Filter

  alias Membrane.{Buffer, H264}

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
    state = %{
      stream_format: nil,
      target_segment_duration: Membrane.Time.seconds(options.segment_duration),
      current_segment_duration: 0,
      last_buffer_pts: nil,
      buffer: [],
      buffer?: true,
      start_time: nil
    }

    {[], state}
  end

  @impl true
  def handle_stream_format(:input, %H264{} = h264, _ctx, state) do
    stream_format = if h264.framerate == nil, do: %H264{h264 | framerate: {0, 0}}, else: h264
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

    {[notify_parent: {:new_media_segment, {nil, state.start_time}}], state}
  end

  @impl true
  def handle_process(:input, %Buffer{} = buf, _ctx, state) do
    frame_duration = buf.pts - state.last_buffer_pts

    state = %{
      state
      | current_segment_duration: state.current_segment_duration + frame_duration,
        last_buffer_pts: buf.pts
    }

    segment_duration = state.current_segment_duration

    cond do
      state.buffer? ->
        state = %{state | buffer: [buf | state.buffer]}
        {[], state}

      buf.metadata.h264.key_frame? and segment_duration >= state.target_segment_duration ->
        pad_ref = state.start_time

        state = %{
          state
          | start_time: state.start_time + segment_duration,
            current_segment_duration: 0,
            buffer?: true,
            buffer: [buf]
        }

        {[
           end_of_stream: Pad.ref(:output, pad_ref),
           notify_parent: {:new_media_segment, {pad_ref, state.start_time}}
         ], state}

      true ->
        {[buffer: {Pad.ref(:output, state.start_time), buf}], state}
    end
  end
end
