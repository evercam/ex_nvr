defmodule ExNVR.Pipeline.Source.Webcam do
  @moduledoc """

      start camera
      capture streams
      streams to the correct format I420
      h264 -> encodes (todo: using video processor)
  """

  alias ExNVR.AV.{Encoder, Frame}
  alias ExNVR.Model.Device

  alias Membrane.Buffer
  alias Membrane.CameraCapture.Native
  alias Membrane.FFmpeg.SWScale.PixelFormatConverter
  alias Membrane.H264
  alias Membrane.H264.FFmpeg.Common
  alias Membrane.H264.FFmpeg.Encoder, as: En

  use Membrane.Source

  @dest_time_base 90_000
  @original_time_base Membrane.Time.seconds(1)

  def_options(
    device: [
      spec: Device.t(),
      description: "The device struct"
    ],
    framerate: [
      spec: non_neg_integer(),
      descriptions: "framerate"
    ]
  )

  def_output_pad(:main_stream_output,
    accepted_format: %H264{alignment: :au},
    availability: :always,
    flow_control: :push
  )

  @impl true
  def handle_init(_ctx, options) do
    {:ok, native} =
      Native.open(options.device, options.framerate)

    {[],
     %{
       device: options.device,
       native: native,
       framerate: options.framerate,
       init_time: Membrane.Time.monotonic_time(),
       pixel_format: nil,
       width: nil,
       height: nil,
       pid: nil
     }}
  end

  def handle_playing(ctx, state) do
    {:ok, width, height, pixel_format} =
      Native.stream_props(state.native)

    stream_format = %H264{
      alignment: :au,
      framerate: state.framerate,
      height: state.height,
      width: state.width,
      profile: :baseline
    }

    state =
      %{state | init_time: state.init_time}

    element_parent_pid = self()

    {:ok, pid} =
      Membrane.UtilitySupervisor.start_link_child(
        ctx.utility_supervisor,
        Supervisor.child_spec(
          {
            Task,
            fn ->
              stream_packets(
                state.native,
                %{
                  state
                  | width: width,
                    height: height,
                    pixel_format: pixel_format_to_atom(pixel_format)
                },
                element_parent_pid
              )
            end
          },
          []
        )
      )

    {[stream_format: {:main_stream_output, stream_format}],
     %{state | pid: pid, pixel_format: pixel_format_to_atom(pixel_format)}}
  end

  def stream_packets(native, state, element_parent_pid) do
    with {:ok, frame} <- Native.read_packet(native),
         # this frames have to be converted to --> 1420 -> encoded ->
         {:ok, input_converter} <-
           PixelFormatConverter.Native.create(
             state.width,
             state.height,
             state.pixel_format,
             :I420
           ),
         {:ok, pixels_in_I420} <-
           PixelFormatConverter.Native.process(input_converter, frame) do
      [h264_packet] = convert_to_h264(pixels_in_I420, state)

      send(element_parent_pid, {:frame, h264_packet})

      stream_packets(native, state, element_parent_pid)
    end
  end

  @impl true
  def handle_info({:frame, frame}, _ctx, state) do
    time = Membrane.Time.monotonic_time()

    stream_format = create_new_stream_format(frame, state)

    {[stream_format: stream_format], state}
  end

  def convert_to_h264(frame, state) do
    time = Membrane.Time.monotonic_time()

    encoder =
      Encoder.new(:h264,
        width: state.width,
        height: state.height,
        format: :yuv420p,
        time_base: {1, @dest_time_base},
        gop_size: 15,
        profile: "Baseline",
        max_b_frames: 0
      )

    frame_details =
      %Frame{
        type: :video,
        data: frame,
        format: :I420,
        width: state.width,
        height: state.height,
        pts: time - state.init_time
      }

    Encoder.encode(encoder, frame_details)

    frame

    Encoder.flush(encoder)
  end

  def new_encoder_ref(state) do
    En.Native.create(
      state.width,
      state.height,
      :I420,
      :medium,
      nil,
      :baseline,
      -1,
      -1,
      1,
      #
      1,
      # crf
      23,
      # threshold
      40,
      []
    )
  end

  defp create_new_stream_format(stream_format, state) do
    {:main_stream_output,
     %H264{
       alignment: :au,
       framerate: state.framerate,
       height: state.height,
       width: state.width,
       profile: :baseline
     }}
  end

  defp pixel_format_to_atom("yuv420p"), do: :I420
  defp pixel_format_to_atom("yuv422p"), do: :I422
  defp pixel_format_to_atom("yuv444p"), do: :I444
  defp pixel_format_to_atom("rgb24"), do: :RGB
  defp pixel_format_to_atom("rgba"), do: :RGBA
  defp pixel_format_to_atom("yuyv422"), do: :YUY2
  defp pixel_format_to_atom("nv12"), do: :NV12
  defp pixel_format_to_atom("nv21"), do: :NV21
end
