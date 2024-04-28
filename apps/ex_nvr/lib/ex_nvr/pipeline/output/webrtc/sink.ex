defmodule ExNVR.Pipeline.Output.WebRTC.Sink do
  @moduledoc false

  use Membrane.Sink

  def_input_pad :input,
    flow_control: :auto,
    accepted_format: _any

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{pid: nil, stream_format: nil, stream?: false}}
  end

  @impl true
  def handle_parent_notification({:source_pid, pid}, _ctx, state) do
    Process.monitor(pid)

    if state.stream? and state.stream_format do
      send(pid, {:stream_format, state.stream_format})
    end

    {[], %{state | pid: pid}}
  end

  @impl true
  def handle_parent_notification({:stream, stream?}, _ctx, state) do
    if not is_nil(state.pid) and stream? and state.stream_format do
      send(state.pid, {:stream_format, state.stream_format})
    end

    {[], %{state | stream?: stream?}}
  end

  @impl true
  def handle_parent_notification(_notification, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    if is_nil(state.pid) or not state.stream? do
      {[], %{state | stream_format: stream_format}}
    else
      send(state.pid, {:stream_format, stream_format})
      {[], state}
    end
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    if is_nil(state.pid) or not state.stream? do
      {[], state}
    else
      send(state.pid, {:buffer, buffer})
      {[], state}
    end
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
