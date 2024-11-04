defmodule ExNVR.Pipeline.Output.HLS.TimestampAdjuster do
  @moduledoc """
  Adjust timestamp offset when `ExNVR.Pipeline.Event.StreamClosed` event.

  When a long session is recorded and a stream is closed, the `dts` and `pts` restart
  from 0 which causes the CMAF element to buffer data until the memory is exhaused.
  """

  use Membrane.Filter

  alias Membrane.Buffer
  alias Membrane.Time

  def_input_pad :input, accepted_format: _any
  def_output_pad :output, accepted_format: _any

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{last_buffer_timestamp: 0, offset: 0, adjust_offset: false}}
  end

  @impl true
  def handle_buffer(_pad, buffer, _ctx, %{adjust_offset: true} = state) do
    offset =
      max(
        0,
        state.last_buffer_timestamp - Buffer.get_dts_or_pts(buffer) + Time.milliseconds(30)
      )

    do_handle_buffer(buffer, %{state | adjust_offset: false, offset: offset})
  end

  @impl true
  def handle_buffer(_pad, buffer, _ctx, state) do
    do_handle_buffer(buffer, state)
  end

  @impl true
  def handle_event(_pad, event, _ctx, state) do
    {[event: {:output, event}], %{state | adjust_offset: true}}
  end

  defp do_handle_buffer(buffer, state) do
    buffer = %{
      buffer
      | dts: buffer.dts && buffer.dts + state.offset,
        pts: buffer.pts + state.offset
    }

    state = %{state | last_buffer_timestamp: Membrane.Buffer.get_dts_or_pts(buffer)}

    {[buffer: {:output, buffer}], state}
  end
end
