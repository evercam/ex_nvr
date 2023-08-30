defmodule ExNVR.Pipelines.BifGenerator do
  @moduledoc """
  Generate BIF files from recorded videos
  """

  use Membrane.Pipeline

  def start_link(options) do
    Pipeline.start_link(__MODULE__, options)
  end

  @impl true
  def handle_init(_ctx, options) do
    spec = [
      child(:source, %ExNVR.Elements.MP4.Depayloader{
        device_id: options[:device_id],
        start_date: options[:start_date],
        end_date: options[:end_date]
      })
      |> child(:parser, Membrane.H264.Parser)
      |> child(:bif, %ExNVR.Pipeline.Output.Bif{
        location: options[:location]
      })
    ]

    {[spec: spec], %{}}
  end

  @impl true
  def handle_child_notification(:end_of_stream, :bif, _ctx, state) do
    {[terminate: :normal], state}
  end
end
