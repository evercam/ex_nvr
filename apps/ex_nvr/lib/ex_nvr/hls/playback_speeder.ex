defmodule ExNVR.HLS.PlaybackSpeeder do
  @moduledoc """
  Rewrites buffers pts according to the prodivded playback rate.
  """

  use Membrane.Filter

  def_input_pad :input,
    demand_mode: :auto,
    demand_unit: :buffers,
    accepted_format: _any,
    availability: :always

  def_output_pad :output,
    demand_mode: :auto,
    accepted_format: _any

  def_options rate: [
                spec: float(),
                default: 1,
                description: """
                The playback speed rate to either speed up or slow down the stream.
                * A value lower than 1: speeds up the stream.
                * A value greater than 1: slows down the stream.
                * 1 is the default value which is the normal stream speed.
                """
              ]

  @impl true
  def handle_init(_ctx, options) do
    state =
      options
      |> Map.from_struct()

    {[], state}
  end

  @impl true
  def handle_process(:input, buffer, _ctx, state) do
    buffer = %{
      buffer
      | pts: trunc(buffer.pts * state.rate),
        dts: trunc(buffer.dts * state.rate)
    }

    {[buffer: {:output, buffer}], state}
  end
end
