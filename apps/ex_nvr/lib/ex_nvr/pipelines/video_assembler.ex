defmodule ExNVR.Pipelines.VideoAssembler do
  @moduledoc """
  A Pipeline to assemble video chunks into one big file.

  The pipeline will read the recorded videos chunks and concatenate
  them into one big file according to the supplied `start_date` and `duration`.
  """

  use Membrane.Pipeline

  require Membrane.Logger

  alias ExNVR.Elements

  @impl true
  def handle_init(_ctx, options) do
    Logger.metadata(device_id: options[:device_id])
    Membrane.Logger.info("Initialize VideoAssembler pipeline with: #{inspect(options)}")

    spec = [
      child(:source, struct(Elements.RecordingBin, options))
      |> via_out(:video)
      |> child(:paylaoder, %Membrane.H264.Parser{output_stream_structure: :avc1})
      |> via_in(Pad.ref(:input, :video_track))
      |> child(:muxer, Membrane.MP4.Muxer.ISOM)
      |> child(:sink, %Membrane.File.Sink{
        location: options[:destination]
      })
    ]

    {[spec: spec], %{device_id: options[:device_id]}}
  end

  @impl true
  def handle_element_end_of_stream(:sink, _pad, _ctx, state) do
    Membrane.Logger.info("Finished assembling video file")
    {[terminate: :shutdown], state}
  end

  @impl true
  def handle_element_end_of_stream(_element, _pad, _ctx, state) do
    {[], state}
  end
end
