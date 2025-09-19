defmodule ExNVR.Pipeline.Source.Webcam do
  @moduledoc false

  @moduledoc """

      start camera
      capture streams
      streams to the correct format I420
      h264 -> encodes (todo: using video processor)
  """
  alias JSON.Encoder
  alias ExNVR.AV.{Decoder, Encoder, Frame}

  use Membrane.Source
  alias Membrane.Buffer

  alias ExNVR.Model.Device
  alias Membrane.H264
  alias Membrane.CameraCapture.Native

  alias Membrane.H264.FFmpeg, as: Encode
  alias Membrane.FFmpeg.SWScale.PixelFormatConverter

  @dest_time_base 90_000

  def_options device: [
                spec: Device.t(),
                description: "The device struct"
              ],
              framerate: [
                spec: non_neg_integer(),
                descriptions: "framerate"
              ]

  def_output_pad :main_stream_output,
    accepted_format: %Membrane.RawVideo{},
    availability: :always,
    flow_control: :push

  @impl true
  def handle_init(_ctx, options) do
    {:ok, native} =
      Native.open(options.device, options.framerate)
      |> IO.inspect(label: "label: ____")

    native
    |> IO.inspect(label: "play mode")

    {[],
     %{
       device: options.device,
       native: native,
       framerate: options.framerate,
       init_time: nil,
       pixel_format: nil,
       width: nil,
       height: nil,
       pid: nil
     }}
  end

  def handle_playing(ctx, state) do
    {:ok, width, height, pixel_format} = Native.stream_props(state.native)

    stream_format = %Membrane.RawVideo{
      width: width,
      height: height,
      pixel_format: :I420,
      aligned: true,
      framerate: {state.framerate, 1}
    }

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

    {[stream_format: {:main_stream_output, stream_format}], %{state | pid: pid}}
  end

  def stream_packets(native, state, element_parent_pid) do
    with {:ok, frame} <- Native.read_packet(native),
         # this frames have to be converted to --> 1420 -> encoded ->
         {:ok, output_converter} <-
           PixelFormatConverter.Native.create(
             state.width,
             state.height,
             state.pixel_format,
             :I420
           ) do
      frame = maybe_convert(frame, output_converter, state.pixel_format, :I420)

      #  convert_to_h264(frame, state) --> this return empty packets [] which is not the correct format
      send(element_parent_pid, {:frame, frame})

      stream_packets(native, state, element_parent_pid)
    end
  end

  @impl true
  def handle_info({:frame, frame}, _ctx, state) do
    time = Membrane.Time.monotonic_time()
    init_time = state.init_time || time
    buffer = %Buffer{payload: frame, pts: time - init_time}
    {[buffer: {:main_stream_output, buffer}], %{state | init_time: init_time}}
  end

  def convert_to_h264(frame, state) do
    time = Membrane.Time.monotonic_time()
    init_time = state.init_time || time

    encoder =
      Encoder.new(:h264,
        width: state.width,
        height: state.height,
        format: :yuv420p,
        time_base: {1, @dest_time_base},
        gop_size: 32,
        profile: "Baseline",
        max_b_frames: 0
      )

    frame_details =
      %Frame{
        type: :video,
        data: frame,
        format: :yuv420p,
        width: state.width,
        height: state.height,
        pts: time - init_time
      }

    Encoder.encode(encoder, frame_details)
  end

  defp maybe_convert(frame, _native_converter, format, format) do
    frame
  end

  defp maybe_convert(payload, native_converter, _source_format, _target_format) do
    with {:ok, frame} <- PixelFormatConverter.Native.process(native_converter, payload) do
      frame
    else
      {:error, reason} ->
        raise "An error has ocurred while processing the buffer: `#{inspect(reason)}`"
    end
  end

  defp frame_provider(native, parent_pid, state) do
    with {:ok, frame} <- Native.read_packet(native) do
      send(parent_pid, {:frame, frame})
      encode_frame_to_h264(frame, state)

      frame_provider(native, parent_pid, state)
    else
      {:error, reason} ->
        raise "Error when reading packets: #{inspect(reason)}"
    end
  end

  def encode_frame_to_h264(frame, state) do
    time = Membrane.Time.monotonic_time()
    init_time = state.init_time || time

    frame_details =
      %{
        type: :video,
        data: frame,
        format: state.pixel_format,
        width: state.width,
        height: state.height,
        pts: time - init_time
      }

    # encode
    encoder =
      Encoder.new(:h264,
        width: state.width,
        height: state.height,
        format: :yuv422p,
        time_base: {1, @dest_time_base},
        gop_size: 32,
        profile: "Baseline",
        max_b_frames: 0
      )
      |> Encoder.encode(frame_details)
  end

  defp pixel_format_to_atom("yuv420p"), do: :I420
  defp pixel_format_to_atom("yuv422p"), do: :I422
  defp pixel_format_to_atom("yuv444p"), do: :I444
  defp pixel_format_to_atom("yuyv422"), do: :YUY2
end
