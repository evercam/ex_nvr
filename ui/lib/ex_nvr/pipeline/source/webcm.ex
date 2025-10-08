defmodule ExNVR.Pipeline.Source.Webcm do
  @moduledoc """
    The system opens the webcam and captures frames in a raw format (such as YUY2, MJPEG, or NV12).
    For our pipeline, we require the frames in I420 (YUV420P) format, which stores full-resolution brightness and sub-sampled color , making it efficient for compression.
    Since webcams often don’t output I420 directly, we convert the frames to this format.
    After conversion, the I420 frames are encoded into H.264, which is the format our pipeline consumes. 
  """
  alias ExNVR.AV.CameraCapture
  alias ExNVR.AV.{Encoder, Frame, Packet}
  use Membrane.Source

  alias Membrane.Buffer
  alias Membrane.H264

  @dest_time_base 90_000
  @original_time_base Membrane.Time.seconds(1)

  defmodule FFmpegParam do
    @moduledoc false
    @enforce_keys [:key, :value]
    defstruct @enforce_keys
  end

  def_output_pad(:output,
    accepted_format: %H264{alignment: :au},
    availability: :always,
    flow_control: :push
  )

  def_options(
    device: [
      spec: String.t(),
      default: "default",
      description: "Name of the device used to capture video"
    ],
    framerate: [
      spec: non_neg_integer(),
      default: 20,
      description: "Framerate of device's output video stream"
    ]
  )

  @impl true
  def handle_init(_ctx, %__MODULE__{} = options) do
    case CameraCapture.open_camera(options.device, to_string(options.framerate)) do
      {:ok, native} ->
        state = %{
          native: native,
          provider: nil,
          framerate: options.framerate,
          width: nil,
          height: nil,
          pixel_format: :yuv420p,
          encoder: nil,
          keyframe_requested?: true
        }

        {[], state}

      {:error, reason} ->
        raise "Failed to initialize camera, reason: #{reason}"
    end
  end

  @impl true
  def handle_setup(_ctx, state) do
    {:ok, frame} = CameraCapture.read_camera_frame(state.native)

    encoder =
      Encoder.new(:h264,
        width: frame.width,
        height: frame.height,
        format: :yuv420p,
        time_base: {1, @dest_time_base},
        gop_size: 32,
        profile: "Baseline",
        max_b_frames: 0
      )

    state =
      %{
        state
        | encoder: encoder,
          width: frame.width,
          height: frame.height
      }

    {[], state}
  end

  @impl true
  def handle_playing(ctx, state) do
    stream_format = create_new_stream_format(state)
    element_pid = self()

    # start child for frames reading
    {:ok, provider} =
      Membrane.UtilitySupervisor.start_link_child(
        ctx.utility_supervisor,
        Supervisor.child_spec({Task, fn -> frame_provider(state.native, element_pid) end}, [])
      )

    state = %{state | provider: provider}
    {[stream_format: stream_format], state}
  end

  @impl true
  def handle_info({:frame, frame}, _ctx, state) do
    # feed the frame to the encoder and it produces an entire frame

    buffer = h264_encoder(state, frame)
    {buffer, %{state | width: frame.width, height: frame.height, pixel_format: frame.format}}
  end

  defp create_new_stream_format(state) do
    {:output,
     %H264{
       alignment: :au,
       stream_structure: :annexb,
       framerate: state.framerate,
       height: state.height,
       width: state.width,
       profile: :baseline
     }}
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

  def h264_encoder(state, frame) do
    case Encoder.encode(state.encoder, frame) do
      [] ->
        []

      [packet] ->
        wrap_frames(packet.dts, packet.pts, packet.data)
    end
  end

  defp wrap_frames([], [], []), do: []

  defp wrap_frames(dts, pts, frames) do
    %Buffer{
      pts: pts,
      dts: dts,
      payload: frames,
      metadata: %{
        h264: %{key_frame?: true},
        timestamp: DateTime.utc_now()
      }
    }
    |> then(&[buffer: {:output, &1}])
  end

  def to_h264_time_base_truncated(timestamp) do
    (timestamp * @dest_time_base / Membrane.Time.second()) |> Ratio.trunc()
  end

  defp flush_encoder_if_exists(%{encoder: nil}), do: []

  defp flush_encoder_if_exists(%{encoder: encoder}) do
    case Encoder.flush(encoder) do
      [packet] ->
        wrap_frames(packet.dts, packet.pts, packet.data)

      [] ->
        []
    end
  end
end
