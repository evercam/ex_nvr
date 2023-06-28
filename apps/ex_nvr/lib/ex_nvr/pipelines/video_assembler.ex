defmodule ExNVR.Pipelines.VideoAssembler do
  @moduledoc """
  A Pipeline to assemble videos chunks into one big file.

  The pipeline will read the recorded videos chunks and concatenate
  them into one big file according to the supplied `start_date` and `duration`.
  """

  use Membrane.Pipeline

  require Membrane.Logger

  alias ExNVR.Elements

  @impl true
  def handle_init(_ctx, options) do
    Membrane.Logger.info("Initialize VideoAssembler pipeline with: #{inspect(options)}")

    spec = [
      child(:source, struct(Elements.MP4.Depayloader, options))
      |> child(:parser, %Membrane.H264.Parser{framerate: {0, 0}})
      |> child(:paylaoder, Membrane.MP4.Payloader.H264)
      |> via_in(Pad.ref(:input, :video_track))
      |> child(:muxer, Membrane.MP4.Muxer.ISOM)
      |> child(:sink, %Membrane.File.Sink{
        location: options[:destination]
      })
    ]

    {[spec: spec, playback: :playing], %{device_id: options[:device_id]}}
  end

  @impl true
  def handle_element_end_of_stream(:sink, _pad, _ctx, state) do
    Membrane.Logger.info("Finished creating video file for #{state.device_id}")
    {[terminate: :shutdown], state}
  end

  @impl true
  def handle_element_end_of_stream(_element, _pad, _ctx, state) do
    {[], state}
  end
end
