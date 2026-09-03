defmodule ExNVR.Support.TestSource do
  @moduledoc false

  use Membrane.Source

  def_output_pad :output,
    flow_control: :push,
    accepted_format: %Membrane.RemoteStream{type: :bytestream}

  @impl true
  def handle_init(_ctx, _opts) do
    {[], nil}
  end

  @impl true
  def handle_parent_notification(actions, _ctx, state) do
    {actions, state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[stream_format: {:output, %Membrane.RemoteStream{type: :bytestream}}], state}
  end
end
