defmodule ExNVR.Pipelines.Dummy do
  @moduledoc """
  Generate BIF files from recorded videos
  """

  use Membrane.Pipeline

  def start(options) do
    Pipeline.start(__MODULE__, options)
  end

  @impl true
  def handle_init(_ctx, _opts) do
    # spec = [
    #   child(:source, %ExNVR.RTSP.Source{
    #     allowed_media_types: [:video],
    #     # stream_uri: "rtsp://admin:Mehcam4Mehcam@wg5.evercam.io:21607/ISAPI/Streaming/channels/101"
    #     stream_uri: "rtsp://admin:Mehcam4Mehcam@192.168.8.110/ISAPI/Streaming/channels/101"
    #   })
    # ]

    spec = [
      child(:source, %Membrane.File.Source{
        location: "test.h264"
      })
      |> child(:a1, %Membrane.H264.Parser{generate_best_effort_timestamps: %{framerate: {30, 1}}})
      |> child(:a2, %Membrane.H264.FFmpeg.Decoder{})
      |> child(:a4, %Membrane.H264.FFmpeg.Encoder{profile: :baseline})
      |> child(:a3, %Membrane.H264.Parser{})
      |> child(:sink, %Membrane.Debug.Sink{handle_buffer: &IO.inspect/1})
    ]

    {[spec: spec], %{}}
  end

  def handle_child_notification({:new_track, ssrc, track}, _element, _ctx, state) do
    IO.inspect(track)

    # spec = [
    #   get_child(:source)
    #   |> via_out(Pad.ref(:output, ssrc))
    #   |> child(:decoder, Membrane.H264.FFmpeg.Decoder)
    #   |> child({:sink, ssrc}, %Membrane.Debug.Sink{
    #     handle_buffer: fn _buffer ->
    #       nil
    #       # {:ok, image} = Image.YUV.new_from_binary(buffer.payload, 3840, 2160, :C420)
    #       # image = Image.thumbnail!(image, 480)

    #       # IO.inspect(Vix.Vips.Image.write_to_binary(image))
    #     end
    #   })
    # ]

    spec = [
      # get_child(:source)
      # |> via_out(Pad.ref(:output, ssrc))
      # |> child(:thumbnailer, %ExNVR.Pipeline.Output.Thumbnailer{
      #   dest: "/tmp",
      #   interval: 10
      # })
    ]

    {[spec: spec], state}
  end
end
