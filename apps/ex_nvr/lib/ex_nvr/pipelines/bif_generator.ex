defmodule ExNVR.Pipelines.BifGenerator do
  @moduledoc """
  Generate BIF files from recorded videos
  """

  use Membrane.Pipeline

  def start(options) do
    Pipeline.start(__MODULE__, options)
  end

  @impl true
  def handle_init(_ctx, options) do
    spec = [
      child(:source, %ExNVR.Elements.RecordingBin{
        device_id: options[:device_id],
        start_date: options[:start_date],
        end_date: options[:end_date],
        strategy: :exact
      })
      |> via_out(:video)
      |> child(:bif, %ExNVR.Pipeline.Output.Bif{
        location: options[:location]
      })
    ]

    {[spec: spec], %{}}
  end

  @impl true
  def handle_child_notification(:end_of_stream, :bif, _ctx, state) do
    {[terminate: :shutdown], state}
  end
end
