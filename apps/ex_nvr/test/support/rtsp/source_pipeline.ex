defmodule ExNVR.RTSP.SourcePipeline do
  @moduledoc false
  use Membrane.Pipeline

  alias ExNVR.Elements.RTSP.Source

  @impl true
  def handle_init(_ctx, options) do
    spec = [child(:source, %Source{stream_uri: options[:stream_uri]})]

    {[spec: spec], %{}}
  end

  @impl true
  def handle_child_notification({:rtsp_setup_complete, _track, ref}, :source, _ctx, state) do
    spec = [
      get_child(:source)
      |> via_out(Pad.ref(:output, ref))
      |> child(:sink, Membrane.Testing.Sink)
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification(_notification, _element, _ctx, state) do
    {[], state}
  end
end
