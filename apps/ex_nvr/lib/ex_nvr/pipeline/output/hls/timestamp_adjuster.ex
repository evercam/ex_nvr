defmodule ExNVR.Pipeline.Output.HLS.TimestampAdjuster do
  @moduledoc """
  Adjust timestamp offset when `ExNVR.Pipeline.Event.StreamClosed` event.

  When a long session is recorded and a stream is closed, the `dts` and `pts` restart
  from 0 which causes the CMAF element to buffer data until the memory is exhaused.
  """

  use Membrane.Filter

  alias ExNVR.Pipeline.Event.StreamClosed

  def_input_pad :input, accepted_format: _any
  def_output_pad :output, accepted_format: _any

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{last_buffer_timestamp: 0, offset: 0}}
  end

  @impl true
  def handle_buffer(_pad, buffer, _ctx, state) do
    buffer = %{
      buffer
      | dts: buffer.dts && buffer.dts + state.offset,
        pts: buffer.pts + state.offset
    }

    state = %{state | last_buffer_timestamp: Membrane.Buffer.get_dts_or_pts(buffer)}

    {[buffer: {:output, buffer}], state}
  end

  @impl true
  def handle_event(_pad, %StreamClosed{}, _ctx, state) do
    # put a 30 millisecond as the duration of the last frame
    offset = state.last_buffer_timestamp + Membrane.Time.milliseconds(30)
    {[], %{last_buffer_timestamp: 0, offset: offset}}
  end

  @impl true
  def handle_event(pad, event, ctx, state) do
    super(pad, event, ctx, state)
  end
end
