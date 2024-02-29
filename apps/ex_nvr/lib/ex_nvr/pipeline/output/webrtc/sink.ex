defmodule ExNVR.Pipeline.Output.WebRTC.Sink do
  @moduledoc false

  use Membrane.Sink

  alias Membrane.Buffer

  def_input_pad :input,
    flow_control: :auto,
    accepted_format: _any

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{pid: nil, stream_format: nil}}
  end

  @impl true
  def handle_parent_notification({:source_pid, pid}, _ctx, state) do
    Process.monitor(pid)

    if state.stream_format do
      send(pid, {:stream_format, state.stream_format})
    end

    {[], %{state | pid: pid}}
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
  def handle_buffer(:input, _buffer, _ctx, %{pid: nil} = state) do
    {[], state}
  end

  @impl true
  def handle_buffer(:input, %Buffer{} = buffer, _ctx, state) do
    send(state.pid, {:buffer, buffer})
    {[], state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, _ctx, %{pid: pid} = state) do
    {[], %{state | pid: nil}}
  end

  @impl true
  def handle_info(_message, _ctx, state) do
    {[], state}
  end
end
