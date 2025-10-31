defmodule ExNVR.Pipeline.Source.Webcam do
  @moduledoc """
    A Membrane element that captures frames from a camera, encodes them to H.264
  """
  use Membrane.Source

  import ExMP4.Helper

  alias ExNVR.AV.CameraCapture
  alias ExNVR.AV.{Encoder, Frame, Packet}
  alias Membrane.Buffer
  alias Membrane.H264

  @dest_time_base 90_000
  @original_time_base Membrane.Time.seconds(1)

  defmodule FFmpegParam do
    @moduledoc false
    @enforce_keys [:key, :value]
    defstruct @enforce_keys
  end

  def_output_pad :main_stream_output,
    accepted_format: %H264{alignment: :au},
    availability: :on_request,
    flow_control: :push

  def_options(
    device: [
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
      spec: {integer(), integer()},
      default: nil,
      description: "Width and height(wxh)"
    ]
  )

  @impl true
  def handle_init(_ctx, %__MODULE__{} = options) do
    {width, height} = options.resolution

    case CameraCapture.open_camera(
           options.device,
           to_string(options.framerate),
           width,
           height
         ) do
      {:ok, native} ->
        state = %{
          native: native,
          provider: nil,
          framerate: options.framerate,
          width: nil,
          height: nil,
          pixel_format: nil,
          encoder: nil,
          track: nil,
          pad: nil,
          init_time: Membrane.Time.monotonic_time()
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
        format: frame.format,
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
          height: frame.height,
          pixel_format: frame.format
      }

    {[], state}
  end

  # handle_playing should notify parent about tracks
  @impl true
  def handle_playing(ctx, state) do
    element_pid = self()

    {:ok, provider} =
      Membrane.UtilitySupervisor.start_link_child(
        ctx.utility_supervisor,
        Supervisor.child_spec({Task, fn -> frame_provider(state.native, element_pid) end}, [])
      )

    track =
      ExNVR.Pipeline.Track.new(:video, :h264)

    state = %{state | provider: provider, track: track}

    action = [
      notify_parent:
        {:main_stream,
         %{
           1 => track
         }}
    ]

    {action, state}
  end

  def handle_pad_added(Pad.ref(:main_stream_output, track_id) = pad, ctx, state) do
    {[stream_format: {pad, create_stream_format(state)}], %{state | pad: pad}}
  end

  @impl true
  def handle_info({:frame, frame}, _ctx, state) do
    # feed the frame to the encoder and it produces an entire frame

    buffer =
      state.encoder
      |> Encoder.encode(frame)
      |> Enum.map(&wrap_into_buffer(&1, state.init_time))

    {[buffer: {state.pad, buffer}], state}
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    buffer = flush_encoder_if_exists(state)
    {buffer, state}
  end

  defp create_stream_format(state) do
    %H264{
      alignment: :au,
      stream_structure: :annexb,
      framerate: state.framerate,
      height: state.height,
      width: state.width,
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

  defp wrap_into_buffer([], _state), do: []

  defp wrap_into_buffer(packet, init_time) do
    time =
      Membrane.Time.monotonic_time() - init_time

    %Buffer{
      dts: time,
      pts: time,
      payload: packet.data,
      metadata: %{
        h264: %{key_frame?: packet.keyframe?},
        timestamp: DateTime.utc_now()
      }
    }
  end

  defp flush_encoder_if_exists(%{encoder: nil}), do: []

  defp flush_encoder_if_exists(%{encoder: encoder}) do
    time = Membrane.Time.monotonic_time()

    case Encoder.flush(encoder) do
      [packet] ->
        wrap_into_buffer(packet, time)

      [] ->
        []
    end
  end
end
