defmodule ExNVR.Elements.Realtimer do
  @moduledoc """
  A wrapper of `Membrane.Realtimer` element that allows a provided duration to
  pass directly before transitioning to realtime.
  """

  use Membrane.Filter

  alias Membrane.{Buffer, Realtimer}

  def_input_pad :input, accepted_format: _any, flow_control: :manual, demand_unit: :buffers
  def_output_pad :output, accepted_format: _any, flow_control: :push

  def_options duration: [
                spec: Membrane.Time.t(),
                default: Membrane.Time.seconds(20),
                description:
                  "The duration of the video to allow before transitioning to realtime streaming"
              ]

  @impl true
  def handle_init(ctx, options) do
    {actions, state} = Realtimer.handle_init(ctx, options)
    {actions, Map.merge(state, %{duration: options.duration, first_buffer_timestamp: nil})}
  end

  @impl true
  def handle_buffer(:input, buffer, ctx, state) do
    timestamp = state.first_buffer_timestamp || Buffer.get_dts_or_pts(buffer)

    if Buffer.get_dts_or_pts(buffer) - timestamp >= state.duration do
      Realtimer.handle_buffer(:input, buffer, ctx, state)
    else
      {[buffer: {:output, buffer}, demand: {:input, 1}],
       %{state | first_buffer_timestamp: timestamp}}
    end
  end

  @impl true
  defdelegate handle_playing(ctx, state), to: Membrane.Realtimer

  @impl true
  defdelegate handle_event(pad, event, ctx, state), to: Membrane.Realtimer

  @impl true
  defdelegate handle_stream_format(pad, stream_format, ctx, state), to: Membrane.Realtimer

  @impl true
  defdelegate handle_end_of_stream(pad, ctx, state), to: Membrane.Realtimer

  @impl true
  defdelegate handle_tick(tick, ctx, state), to: Membrane.Realtimer
end
