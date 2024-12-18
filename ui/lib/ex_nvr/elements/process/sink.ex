defmodule ExNVR.Elements.Process.Sink do
  @moduledoc """
  Element that sends buffers to another process
  """

  use Membrane.Sink

  alias Membrane.Buffer

  def_input_pad :input,
    flow_control: :auto,
    accepted_format: _any

  def_options pid: [
                spec: pid(),
                description: "Pid of the destination process"
              ]

  @impl true
  def handle_init(_ctx, opts) do
    {[], %{pid: opts.pid}}
  end

  @impl true
  def handle_buffer(:input, %Buffer{} = buffer, _ctx, state) do
    send(state.pid, {:buffer, buffer.payload})
    {[], state}
  end
end
