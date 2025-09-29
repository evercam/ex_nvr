defmodule ExNVR.Pipeline.Source.Webcm do
  @moduledoc """
      start camera
      capture streams

      stream them as raw

  """
  alias JSON.Encoder
  alias JSON.Encoder
  alias Membrane.RawVideo
  alias Membrane.CameraCapture.Native
  alias Membrane.FFmpeg.SWScale.PixelFormatConverter

  alias Membrane.H264.FFmpeg.Common
  alias ExNVR.AV.{Encoder, Frame}
  alias Membrane.H264.FFmpeg.Encoder, as: En
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
    with {:ok, native} <- Native.open(options.device, options.framerate) do
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
        keyframe_requested?: true
      }

      {[], state}
    else
      {:error, reason} -> raise "Failed to initialize camera, reason: #{reason}"
    end
  end

  @impl true
  def handle_setup(_ctx, state) do
    with {:ok, width, height, pixel_format} <- Native.stream_props(state.native),
         {:ok, encoder_ref} <-
           encoder_ref(%{
             width: width,
             height: height,
             framerate: state.framerate,
             ffmpeg_params: state.ffmpeg_params
           }) do
      state = %{
        state
        | width: width,
          height: height,
          pixel_format: pixel_format,
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
    with {:ok, output_converter} <-
           PixelFormatConverter.Native.create(
             state.width,
             state.height,
             pixel_format_to_atom(state.pixel_format),
             :I420
           ),
         {:ok, payload} <- PixelFormatConverter.Native.process(output_converter, frame) do
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
    with {:ok, frame} <- Native.read_packet(native) do
      send(target, {:frame, frame})
      frame_provider(native, target)
    else
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
    with {:ok, dts_list, pts_list, frames} <- Native.flush(use_shm?, encoder_ref) do
      wrap_frames(dts_list, pts_list, frames)
    else
      {:error, reason} -> raise "Native encoder failed to flush: #{inspect(reason)}"
    end
  end

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
