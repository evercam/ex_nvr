defmodule ExNVR.Pipeline.Source.Webcam do
  @moduledoc """
    A Membrane element that captures frames from a camera, encodes them to H.264
  """
  use Membrane.Source

  alias ExNVR.AV.{CameraCapture, Encoder}
  alias ExNVR.Pipeline.Track
  alias Membrane.{Buffer, H264}

  @time_base Membrane.Time.seconds(1)

  def_output_pad :main_stream_output,
    accepted_format: %H264{alignment: :au},
    availability: :on_request,
    flow_control: :push

  def_options device: [
                spec: String.t(),
                default: "default",
                description: "Name of the device used to capture video"
              ],
              framerate: [
                spec: non_neg_integer(),
                default: 8,
                description: "Framerate of device's output video stream"
              ],
              resolution: [
                spec: String.t() | nil,
                default: nil,
                description: "Width and height in WIDTHxHEIGHT format"
              ]

  @impl true
  def handle_init(_ctx, %__MODULE__{} = options) do
    {[],
     %{
       native: nil,
       provider: nil,
       encoder: nil,
       timebase: nil,
       stream_format: nil,
       linked?: false,
       resolution: options.resolution,
       framerate: options.framerate,
       device: options.device
     }}
  end

  @impl true
  def handle_setup(_ctx, state) do
    with {:ok, ref} <- CameraCapture.open_camera(state.device, state.framerate, state.resolution),
         {:ok, stream_props} <- CameraCapture.get_stream_properties(ref) do
      {width, height, timebase} = stream_props

      encoder =
        Encoder.new(:h264,
          width: width,
          height: height,
          format: :yuv420p,
          time_base: timebase,
          gop_size: 32,
          profile: "Baseline",
          max_b_frames: 0,
          tune: :zerolatency,
          preset: :fast
        )

      {[],
       %{
         state
         | native: ref,
           encoder: encoder,
           stream_format: create_stream_format(width, height),
           timebase: timebase
       }}
    else
      {:error, reason} ->
        {[notify_parent: {:stream_failed, reason}], state}
    end
  end

  @impl true
  def handle_playing(_ctx, %{native: nil} = state), do: {[], state}

  @impl true
  def handle_playing(ctx, state) do
    element_pid = self()

    {:ok, provider} =
      Membrane.UtilitySupervisor.start_link_child(
        ctx.utility_supervisor,
        Supervisor.child_spec({Task, fn -> frame_provider(state.native, element_pid) end}, [])
      )

    {[notify_parent: {:main_stream, %{1 => Track.new(:video, :h264)}}],
     %{state | provider: provider}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:main_stream_output, 1) = pad, _ctx, state) do
    {[stream_format: {pad, state.stream_format}], %{state | linked?: true}}
  end

  @impl true
  def handle_info({:frame, _frame}, _ctx, %{linked?: false} = state), do: {[], state}

  def handle_info({:frame, frame}, _ctx, state) do
    buffers =
      state.encoder
      |> Encoder.encode(frame)
      |> Enum.map(&wrap_into_buffer(&1, state.timebase))

    {[buffer: {Pad.ref(:main_stream_output, 1), buffers}], state}
  end

  defp create_stream_format(width, height) do
    %H264{
      alignment: :au,
      stream_structure: :annexb,
      height: height,
      width: width,
      profile: :baseline
    }
  end

  defp frame_provider(native, target) do
    case CameraCapture.read_camera_frame(native) do
      {:ok, frame} ->
        send(target, {:frame, frame})
        frame_provider(native, target)

      {:error, reason} ->
        raise "Error when reading packet from camera: #{inspect(reason)}"
    end
  end

  defp wrap_into_buffer(packet, {num, den}) do
    %Buffer{
      dts: div(packet.pts * @time_base * num, den),
      pts: div(packet.pts * @time_base * num, den),
      payload: packet.data,
      metadata: %{
        h264: %{key_frame?: packet.keyframe?},
        timestamp: DateTime.utc_now()
      }
    }
  end
end
