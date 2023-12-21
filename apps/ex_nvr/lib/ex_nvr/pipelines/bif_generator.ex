defmodule ExNVR.Pipelines.BifGenerator do
  @moduledoc """
  Generate BIF files from recorded videos
  """

  use Membrane.Pipeline

  alias Membrane.{H264, H265}

  def start(options) do
    Pipeline.start(__MODULE__, options)
  end

  @impl true
  def handle_init(_ctx, options) do
    spec = [
      child(:source, %ExNVR.Elements.RecordingBin{
        device: options[:device],
        start_date: options[:start_date],
        end_date: options[:end_date],
        strategy: :exact
      })
    ]

    {[spec: spec], %{location: options[:location]}}
  end

  @impl true
  def handle_child_notification({:track, track}, :source, _ctx, state) do
    encoding =
      case track do
        %H264{} -> :H264
        %H265{} -> :H265
      end

    spec = [
      get_child(:source)
      |> via_out(:video)
      |> child(:bif, %ExNVR.Pipeline.Output.Bif{
        location: state.location,
        encoding: encoding
      })
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification(:end_of_stream, :bif, _ctx, state) do
    {[terminate: :shutdown], state}
  end
end
