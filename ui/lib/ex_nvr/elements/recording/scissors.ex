defmodule ExNVR.Elements.Recording.Scissors do
  @moduledoc """
  Cut the recording stream depending on two conditions: end date or duration
  """

  use Membrane.Filter

  import ExNVR.Utils, only: [keyframe: 1]

  def_options start_date: [
                spec: Membrane.Time.t(),
                description: """
                Allow all buffers that have a timestamp greater than this date to pass

                Some buffers with timestamp less than this date may pass depending on
                the `start_mode` option.
                """
              ],
              strategy: [
                spec: :keyframe_before | :keyframe_after | :exact,
                default: :keyframe_before,
                description: """
                The strategy to use for selecting the first buffer to pass.

                The following strategy are available:
                  * `keyframe_before` - the first buffer will be keyframe before the start date
                  * `keyframe_after` - the first buffer will be a keyframe after the start date
                  * `exact` - start from the exact timestamp even when the buffer is not a keyframe
                """
              ],
              end_date: [
                spec: Membrane.Time.t(),
                default: Membrane.Time.from_datetime(~U(2099-01-01 00:00:00Z)),
                description: """
                The end date of the last buffer before sending `end_of_stream`
                """
              ],
              duration: [
                spec: Membrane.Time.t(),
                default: 0,
                description: """
                The total duration of the stream before sending `end_of_stream`.

                Note that if both `duration` and `end_of_date` are provided, an
                `end_of_stream` will be sent on the first satisfied condition.
                """
              ]

  def_input_pad :input, flow_control: :auto, accepted_format: _any
  def_output_pad :output, flow_control: :auto, accepted_format: _any

  @impl true
  def handle_init(_ctx, opts) do
    state =
      Map.from_struct(opts)
      |> Map.merge(%{
        pending_buffers: [],
        state: :waiting,
        first_buffer_ts: nil
      })

    {[], state}
  end

  @impl true
  def handle_parent_notification(:end_of_stream, ctx, state) do
    do_handle_end_of_stream(ctx, state)
  end

  @impl true
  def handle_end_of_stream(:input, ctx, state) do
    do_handle_end_of_stream(ctx, state)
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, %{state: :playing} = state) do
    stream_duration = Membrane.Buffer.get_dts_or_pts(buffer) - state.first_buffer_ts

    cond do
      buffer.metadata.timestamp >= state.end_date ->
        {[end_of_stream: :output], %{state | state: :end_of_stream}}

      state.duration != 0 and stream_duration >= state.duration ->
        {[buffer: {:output, buffer}, end_of_stream: :output], %{state | state: :end_of_stream}}

      true ->
        {[buffer: {:output, buffer}], state}
    end
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, %{state: :waiting} = state) do
    do_handle_buffer(buffer, state)
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, %{state: :waiting_for_keyframe} = state)
      when keyframe(buffer) do
    buffer_ts = Membrane.Buffer.get_dts_or_pts(buffer)

    duration =
      if state.duration != 0 do
        state.duration + state.first_buffer_ts - buffer_ts
      else
        state.duration
      end

    {[buffer: {:output, buffer}],
     %{state | state: :playing, duration: duration, first_buffer_ts: buffer_ts}}
  end

  @impl true
  def handle_buffer(:input, _buffer, _ctx, state) do
    {[], state}
  end

  defp do_handle_end_of_stream(ctx, state) do
    if ctx.pads.output.end_of_stream? do
      {[], state}
    else
      {[end_of_stream: :output], state}
    end
  end

  defp do_handle_buffer(buffer, %{strategy: :exact} = state)
       when buffer.metadata.timestamp >= state.start_date do
    {[buffer: {:output, buffer}],
     %{state | state: :playing, first_buffer_ts: Membrane.Buffer.get_dts_or_pts(buffer)}}
  end

  defp do_handle_buffer(buffer, %{strategy: :keyframe_after} = state)
       when buffer.metadata.timestamp >= state.start_date do
    {[],
     %{
       state
       | state: :waiting_for_keyframe,
         first_buffer_ts: Membrane.Buffer.get_dts_or_pts(buffer)
     }}
  end

  defp do_handle_buffer(buffer, %{strategy: :keyframe_before} = state)
       when buffer.metadata.timestamp >= state.start_date do
    buffers = [buffer | state.pending_buffers] |> Enum.reverse()

    {[buffer: {:output, buffers}],
     %{
       state
       | state: :playing,
         pending_buffers: [],
         first_buffer_ts: Membrane.Buffer.get_dts_or_pts(buffer)
     }}
  end

  defp do_handle_buffer(buffer, %{strategy: :keyframe_before} = state) when keyframe(buffer) do
    {[], %{state | pending_buffers: [buffer]}}
  end

  defp do_handle_buffer(buffer, %{strategy: :keyframe_before} = state) do
    {[], %{state | pending_buffers: [buffer | state.pending_buffers]}}
  end

  defp do_handle_buffer(_buffer, state) do
    {[], state}
  end
end
