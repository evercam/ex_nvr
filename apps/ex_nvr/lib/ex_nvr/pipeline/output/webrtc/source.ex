defmodule ExNVR.Pipeline.Output.WebRTC.Source do
  @moduledoc false

  use Membrane.Source

  def_output_pad :output,
    demand_unit: :buffers,
    accepted_format: _any,
    availability: :always,
    flow_control: :push

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{}}
  end

  @impl true
  def handle_setup(_ctx, state) do
    {[notify_parent: {:pid, self()}], state}
  end

  @impl true
  def handle_parent_notification({:stream_format, stream_format}, _ctx, state) do
    {[stream_format: {:output, stream_format}], state}
  end

  @impl true
  def handle_parent_notification({:buffer, buffer}, _ctx, state) do
    {[buffer: {:output, buffer}], state}
  end

  @impl true
  def handle_parent_notification(_notification, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_info({:stream_format, stream_format}, _ctx, state) do
    {[stream_format: {:output, stream_format}], state}
  end

  @impl true
  def handle_info({:buffer, buffer}, _ctx, state) do
    {[buffer: {:output, buffer}], state}
  end

  @impl true
  def handle_info(_message, _ctx, state), do: {[], state}
end
