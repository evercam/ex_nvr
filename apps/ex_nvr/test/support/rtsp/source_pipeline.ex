defmodule ExNVR.RTSP.SourcePipeline do
  @moduledoc false
  use Membrane.Pipeline

  alias ExNVR.Pipeline.Source.RTSP.Source

  @impl true
  def handle_init(_ctx, options) do
    spec = [child(:source, %Source{stream_uri: options[:stream_uri], stream_types: [:video]})]

    {[spec: spec], %{}}
  end

  @impl true
  def handle_child_notification({:rtsp_setup_complete, _tracks}, :source, _ctx, state) do
    spec = [
      get_child(:source)
      |> via_out(Pad.ref(:output, make_ref()))
      |> child(:sink, Membrane.Testing.Sink)
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification(_notification, _element, _ctx, state) do
    {[], state}
  end
end
