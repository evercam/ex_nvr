defmodule ExNVR.Elements.Process.Sink do
  @moduledoc false

  use Membrane.Sink

  alias Membrane.Buffer

  def_input_pad :input,
    demand_unit: :buffers,
    flow_control: :auto,
    accepted_format: _any

  def_options pid: [
                spec: pid(),
                description: "The process' pid where to send buffers"
              ]

  @impl true
  def handle_init(_ctx, opts) do
    {[], %{pid: opts.pid}}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    send(state.pid, {:stream_format, stream_format})
    {[], state}
  end

  @impl true
  def handle_write(:input, %Buffer{} = buffer, _ctx, state) do
    send(state.pid, {:buffer, buffer})
    {[], state}
  end
end
