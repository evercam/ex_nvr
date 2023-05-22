defmodule ExNVR.Elements.HLS.Forwarder do
  @moduledoc """
  Element responsible for discarding all access units before a keyframe is seen
  """

  use Membrane.Filter

  alias Membrane.H264

  def_input_pad :input,
    demand_unit: :buffers,
    demand_mode: :auto,
    accepted_format: %H264{alignment: :au},
    availability: :always

  def_output_pad :output,
    demand_mode: :auto,
    accepted_format: %H264{alignment: :au},
    availability: :always

  @impl true
  def handle_init(_ctx, _options) do
    {[], %{seen_keyframe?: false}}
  end

  @impl true
  def handle_process(_pad, buffer, _ctx, %{seen_keyframe?: false} = state) do
    if buffer.metadata.h264.key_frame? do
      {[forward: buffer], %{state | seen_keyframe?: true}}
    else
      {[], state}
    end
  end

  @impl true
  def handle_process(_pad, buffer, _ctx, state) do
    {[forward: buffer], state}
  end
end
