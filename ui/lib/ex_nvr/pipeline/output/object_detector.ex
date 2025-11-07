defmodule ExNVR.Pipeline.Output.ObjectDetector do
  @moduledoc false

  use Membrane.Sink

  require ExNVR.Utils
  require Membrane.Logger

  import ExNVR.MediaUtils, only: [to_annexb: 1]

  require Logger
  alias ExNVR.AV.{ByteTracker, Decoder, Hailo}
  alias Membrane.{H264, H265}

  def_input_pad :input,
    accepted_format:
      any_of(
        %H264{alignment: :au},
        %H265{alignment: :au}
      )

  def_options hef_file: [
                spec: Path.t()
              ]

  @impl true
  def handle_init(_ctx, options) do
    {:ok, model} = Hailo.load(options.hef_file)
    {:ok, server_sock} = :gen_tcp.listen(5000, [:binary, active: false, reuseaddr: true])

    pid = self()

    spawn(fn ->
      accept_loop(server_sock, pid)
    end)

    state = %{model: model, decoder: nil, tracker: ExNVR.AV.ByteTracker.new(), socket: nil}

    Process.set_label(:object_detector)

    {[], state}
  end

  defp accept_loop(server_sock, pid) do
    {:ok, sock} = :gen_tcp.accept(server_sock)
    send(pid, {:socket, sock})
    accept_loop(server_sock, pid)
  end

  @impl true
  def handle_stream_format(:input, format, ctx, state) do
    old_stream_format = ctx.pads.input.stream_format

    if is_nil(old_stream_format) or old_stream_format != format do
      codec = if is_struct(format, H264), do: :h264, else: :hevc
      decoder = Decoder.new(codec, out_height: 640, out_width: 640, out_format: :rgb24, pad: true)
      {[], %{state | decoder: decoder}}
    else
      {[], state}
    end
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    state = state.decoder
    |> Decoder.decode(to_annexb(buffer.payload), pts: buffer.pts)
    |> Enum.reduce(state, fn frame, state ->
      {:ok, detections} =
        Hailo.infer(
          state.model,
          %{"yolov11l/input_layer1" => frame.data},
          Hailo.Parsers.YoloV8,
          key: "yolov11l/yolov8_nms_postprocess",
          classes: %{}
        )

      detections =
        detections
        |> Enum.filter(&(&1.class_id == 0 && &1.score >= 0.5))
        |> Hailo.Parsers.YoloV8.postprocess({frame.height, frame.width})

      mat = Evision.Mat.from_binary(frame.data, :u8, frame.height, frame.width, 3)

      if state.socket != nil do
        frame =
          detections
          |> Enum.reduce(
            mat,
            &Evision.rectangle(&2, {&1.xmin, &1.ymin}, {&1.xmax, &1.ymax}, {0, 255, 0})
          )
          |> Evision.Mat.to_binary()

        case :gen_tcp.send(state.socket, frame) do
          :ok -> state
          _error -> %{state | socket: nil}
        end
      else
        state
      end

      # tracks = detections |> Enum.filter(& &1.class_id == 0) |> ByteTracker.update(state.tracker)
      # if tracks != [] do
      #   IO.inspect(tracks) |> Logger.info()
      # end
    end)

    {[], state}
  end

  def handle_info({:socket, sock}, _ctx, state) do
    {[], %{state | socket: sock}}
  end
end
