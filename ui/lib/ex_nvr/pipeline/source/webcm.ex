defmodule ExNVR.Pipeline.Source.Webcm do
  @moduledoc """
      start camera
      capture streams

      stream them as raw

  """
  alias ExNVR.AV.CameraCapture
  alias ExNVR.AV.PixelConverter

  alias Membrane.H264.FFmpeg.Common
  alias Membrane.H264.FFmpeg.Encoder, as: En
  alias ExNVR.AV.{Encoder, Frame}
  alias Membrane.H264
  use Membrane.Source

  alias Membrane.Buffer

  @dest_time_base 90_000
  @original_time_base Membrane.Time.seconds(1)
  @profile :baseline
  @preset :medium
  @tune nil
  @use_shm? false
  @max_b_frames 0
  @gop_size 32
  @sc_threshold 30

  @default_crf 23
  @ffmpeg_params %{}
  @present :medium
  @pixel_format :I420

  @default_height 640
  @default_width 360

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
      default: 30,
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
          init_time: Membrane.Time.monotonic_time(),
          framerate: options.framerate,
          width: nil,
          height: nil,
          pixel_format: nil,
          ffmpeg_params: %{},
          encoder_ref: nil,
          ref: nil,
          keyframe_requested?: true
        }

        {[], state}

      {:error, reason} ->
        raise "Failed to initialize camera, reason: #{reason}"
    end
  end

  @impl true
  def handle_setup(_ctx, state) do
    with {:ok, {width, height, pixel_format}} <-
           CameraCapture.camera_stream_props(state.native)

    {:ok, encoder_ref} <-
      encoder_ref(%{
        width: default_if_zero(width, @default_width),
        height: default_if_zero(height, @default_height),
        framerate: state.framerate,
        ffmpeg_params: state.ffmpeg_params
      }) do
        width = default_if_zero(width, @default_width)
        height = default_if_zero(height, @default_height)

        opts = [
          width: width,
          height: height,
          pix_fmt: ~c"I420",
          preset: ~c"medium",
          tune: ~c"zerolatency",
          profile: ~c"baseline",
          max_b_frames: 2,
          gop_size: 20,
          # numerator/denominator for frame timing
          time_base: {1, state.framerate},
          crf: 23,
          sc_threshold: 40
        ]

        state =
          %{
            state
            | width: width,
              height: height,
              pixel_format: to_string(pixel_format),
              encoder_ref: encoder_ref
          }

        {[], state}
      end
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
    handle_frame_convertion(state, frame)
    # try to encode the information
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    buffers = flush_encoder_if_exists(state)
    actions = buffers ++ [end_of_stream: :output]
    {actions, state}
  end

  defp handle_frame_convertion(state, frame) do
    time =
      (Membrane.Time.monotonic_time() - state.init_time)
      |> Common.to_h264_time_base_truncated()

    with {:ok, output_converter} <-
           PixelConverter.create_converter(
             state.width,
             state.height,
             pixel_format_to_atom(state.pixel_format) |> Atom.to_charlist(),
             ~c"I420"
           ),
         {:ok, payload} <- PixelConverter.convert_pixels(output_converter, frame) do
      buffer = h264_encoder(state, payload)
      {buffer, state}
    end
  end

  defp create_new_stream_format(state) do
    {:output,
     %H264{
       alignment: :au,
       stream_structure: :annexb,
       framerate: state.framerate,
       height: state.height,
       width: state.width,
       profile: nil
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

  def h264_encoder(state, payload) do
    time =
      (Membrane.Time.monotonic_time() - state.init_time)
      |> Common.to_h264_time_base_truncated()

    with {:ok, dts, pts, frames} <-
           En.Native.encode(
             payload,
             time,
             @use_shm?,
             state.keyframe_requested?,
             state.encoder_ref
           ) do
      wrap_frames(dts, pts, frames)
    end
  end

  def encoder_ref(state) do
    ffmpeg_params =
      Enum.map(state.ffmpeg_params, fn {key, value} -> %FFmpegParam{key: key, value: value} end)

    En.Native.create(
      state.width,
      state.height,
      :I420,
      @present,
      @tune,
      nil,
      @max_b_frames,
      @gop_size,
      1,
      state.framerate,
      @default_crf,
      @sc_threshold,
      ffmpeg_params
    )
  end

  defp wrap_frames([], [], []), do: []

  defp wrap_frames(dts_list, pts_list, frames) do
    Enum.zip([dts_list, pts_list, frames])
    |> Enum.map(fn {dts, pts, frame} ->
      %Buffer{
        pts: Common.to_membrane_time_base_truncated(pts),
        dts: Common.to_membrane_time_base_truncated(dts),
        payload: frame,
        metadata: %{
          h264: %{key_frame?: true},
          timestamp: DateTime.utc_now()
        }
      }
    end)
    |> then(&[buffer: {:output, &1}])
  end

  defp flush_encoder_if_exists(%{encoder_ref: nil}), do: []

  defp flush_encoder_if_exists(%{encoder_ref: encoder_ref, use_shm?: use_shm?}) do
    case Native.flush(use_shm?, encoder_ref) do
      {:ok, dts_list, pts_list, frames} ->
        wrap_frames(dts_list, pts_list, frames)

      {:error, reason} ->
        raise "Native encoder failed to flush: #{inspect(reason)}"
    end
  end

  defp default_if_zero(value, default), do: if(value == 0, do: default, else: value)

  defp pixel_format_to_atom("yuv420p"), do: :I420
  defp pixel_format_to_atom("yuv422p"), do: :I422
  defp pixel_format_to_atom("yuv444p"), do: :I444
  defp pixel_format_to_atom("rgb24"), do: :RGB
  defp pixel_format_to_atom("rgba"), do: :RGBA
  defp pixel_format_to_atom("yuyv422"), do: :YUY2
  defp pixel_format_to_atom("nv12"), do: :NV12
  defp pixel_format_to_atom("nv21"), do: :NV21

  defp pixel_format_to_atom(pixel_format),
    do: raise("unsupported pixel format #{inspect(pixel_format)}")
end
