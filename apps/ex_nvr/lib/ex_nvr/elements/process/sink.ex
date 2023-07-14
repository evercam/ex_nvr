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
    {[], %{pid: opts.pid, stream_format: nil}}
  end

  @impl true
  def handle_parent_notification({:source_pid, pid}, _ctx, state) do
    actions =
      if state.stream_format do
        [stream_format: {:output, state.stream_format}]
      else
        []
      end

    {actions, %{state | pid: pid}}
  end

  @impl true
  def handle_parent_notification(_notification, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, %{pid: nil} = state) do
    {[], %{state | stream_format: stream_format}}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, %{pid: pid} = state) do
    send(pid, {:stream_format, stream_format})
    {[], state}
  end

  @impl true
  def handle_write(:input, _buffer, _ctx, %{pid: nil} = state) do
    {[], state}
  end

  @impl true
  def handle_write(:input, %Buffer{} = buffer, _ctx, state) do
    send(state.pid, {:buffer, buffer})
    {[], state}
  end
end
