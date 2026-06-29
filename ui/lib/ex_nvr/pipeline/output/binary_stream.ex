defmodule ExNVR.Pipeline.Output.BinaryStream do
  @moduledoc """
  Forward raw H264/H265 access units to subscribed Elixir processes.

  Each binary frame message sent to subscribers has the format:
    {:hevc_frame, nal_units}

  Where nal_units is a list of raw NAL unit binaries (without start codes).
  """

  use Membrane.Sink

  require ExNVR.Utils

  alias Membrane.{H264, H265}

  def_input_pad :input, accepted_format: any_of(%H264{alignment: :au}, %H265{alignment: :au})

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{subscribers: [], keyframe?: false}}
  end

  @impl true
  def handle_parent_notification({:add_subscriber, pid}, _ctx, state) do
    Process.monitor(pid)
    {[], %{state | subscribers: [pid | state.subscribers]}}
  end

  @impl true
  def handle_buffer(:input, _buffer, _ctx, %{subscribers: []} = state), do: {[], state}

  @impl true
  def handle_buffer(:input, buffer, ctx, %{keyframe?: false} = state)
      when ExNVR.Utils.keyframe(buffer) do
    handle_buffer(:input, buffer, ctx, %{state | keyframe?: true})
  end

  @impl true
  def handle_buffer(:input, _buffer, _ctx, %{keyframe?: false} = state), do: {[], state}

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    Enum.each(state.subscribers, &send(&1, {:hevc_frame, buffer.payload}))
    {[], state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, _ctx, state) do
    subscribers = List.delete(state.subscribers, pid)

    if Enum.empty?(subscribers) do
      {[notify_parent: :no_subscribers], %{state | subscribers: []}}
    else
      {[], %{state | subscribers: subscribers}}
    end
  end
end
