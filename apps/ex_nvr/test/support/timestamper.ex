defmodule ExNVR.Support.Timestamper do
  @moduledoc """
  Generate timestamps for a stream
  """

  use Membrane.Filter

  def_input_pad :input,
    demand_mode: :auto,
    demand_unit: :buffers,
    accepted_format: _any

  def_output_pad :output,
    demand_mode: :auto,
    accepted_format: _any

  def_options framerate: [spec: {pos_integer(), pos_integer()}]

  @impl true
  def handle_init(_ctx, opts) do
    {[], %{counter: 0, framerate: opts.framerate}}
  end

  @impl true
  def handle_process(:input, buffer, _ctx, %{framerate: {frames, seconds}} = state) do
    dts = div(state.counter * seconds * Membrane.Time.second(), frames)
    {[buffer: {:output, %{buffer | dts: dts, pts: dts}}], %{state | counter: state.counter + 1}}
  end
end
