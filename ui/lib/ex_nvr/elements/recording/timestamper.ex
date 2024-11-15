defmodule ExNVR.Elements.Recording.Timestamper do
  @moduledoc """
  Correct DTS/PTS of recording files and attach date time of each buffer
  """

  use Membrane.Filter

  def_options offset: [
                spec: Membrane.Time.t(),
                description: "The offset value to add to each buffer dts/pts."
              ],
              start_date: [
                spec: Membrane.Time.t(),
                description: "The start date of the first buffer"
              ]

  def_input_pad :input,
    flow_control: :auto,
    accepted_format: _any,
    availability: :always

  def_output_pad :output,
    flow_control: :auto,
    accepted_format: _any

  @impl true
  def handle_init(_ctx, options) do
    {[],
     %{
       offset: options.offset,
       start_date: options.start_date,
       last_buffer_dts_or_pts: nil
     }}
  end

  @impl true
  def handle_buffer(:input, buffer, ctx, %{last_buffer_dts_or_pts: nil} = state) do
    handle_buffer(:input, buffer, ctx, %{
      state
      | last_buffer_dts_or_pts: Membrane.Buffer.get_dts_or_pts(buffer)
    })
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    buffer_duration = Membrane.Buffer.get_dts_or_pts(buffer) - state.last_buffer_dts_or_pts
    metadata = Map.put(buffer.metadata, :timestamp, state.start_date + buffer_duration)

    buffer = %{
      buffer
      | pts: buffer.pts + state.offset,
        dts: buffer.dts + state.offset,
        metadata: metadata
    }

    {[buffer: {:output, buffer}], state}
  end
end
