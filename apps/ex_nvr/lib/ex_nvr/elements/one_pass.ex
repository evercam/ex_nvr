defmodule ExNVR.Elements.OnePass do
  @moduledoc """
  Element that only allows the first or last buffer to pass.

  When working on `last` mode, the buffer will be sent only when the end of stream
  event is received.
  """

  use Membrane.Filter

  def_input_pad :input,
    flow_control: :manual,
    demand_unit: :buffers,
    accepted_format: _any

  def_output_pad :output,
    flow_control: :manual,
    accepted_format: _any,
    availability: :always

  def_options allow: [
                spec: :first | :last,
                default: :first,
                description: "Allow the first or last buffer to pass down the pipeline"
              ]

  @impl true
  def handle_init(_ctx, options) do
    state =
      options
      |> Map.from_struct()
      |> Map.put(:last_buffer, nil)

    {[], state}
  end

  @impl true
  def handle_demand(:output, _size, :buffers, _ctx, state) do
    {[demand: :input], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, %{allow: :first} = state) do
    {[buffer: {:output, buffer}, end_of_stream: :output], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    {[demand: :input], %{state | last_buffer: buffer}}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, %{allow: :first} = state) do
    {[], state}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    buffer_action =
      if state.last_buffer do
        [buffer: {:output, state.last_buffer}]
      else
        []
      end

    {buffer_action ++ [end_of_stream: :output], state}
  end
end
