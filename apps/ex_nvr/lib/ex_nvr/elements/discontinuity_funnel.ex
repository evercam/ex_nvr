defmodule ExNVR.Elements.DiscontinuityFunnel do
  @moduledoc """
  A funnel element that send a discontinuity event when all pads are removed.
  """

  use Membrane.Filter

  alias Membrane.Funnel

  def_input_pad :input, accepted_format: _any, flow_control: :auto, availability: :on_request
  def_output_pad :output, accepted_format: _any, flow_control: :auto

  @impl true
  def handle_init(_ctx, _opts), do: {[], nil}

  @impl true
  defdelegate handle_buffer(pad, buffer, ctx, state), to: Funnel

  @impl true
  defdelegate handle_pad_added(pad, ctx, state), to: Funnel

  @impl true
  def handle_pad_removed(Pad.ref(:input, _ref), _ctx, state) do
    {[event: {:output, %Membrane.Event.Discontinuity{}}], state}
  end

  @impl true
  def handle_end_of_stream(_pad, _ctx, state) do
    {[event: {:output, %Membrane.Event.Discontinuity{}}], state}
  end
end
