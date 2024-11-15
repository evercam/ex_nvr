defmodule ExNVR.Pipeline.Output.WebRTC.Source do
  @moduledoc false

  use Membrane.Source

  def_output_pad :output,
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
  def handle_info({:buffer, buffer}, ctx, state) do
    if stream_format_sent?(ctx) do
      {[buffer: {:output, buffer}], state}
    else
      {[], state}
    end
  end

  @impl true
  def handle_info(_message, _ctx, state), do: {[], state}

  defp stream_format_sent?(%{pads: %{output: %{stream_format: nil}}}), do: false
  defp stream_format_sent?(_ctx), do: true
end
