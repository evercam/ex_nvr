defmodule ExNVR.Pipeline.Output.ObjectDetection.Inferer do
  @moduledoc false

  use Membrane.Filter

  require Membrane.Logger

  require Logger
  alias ExNVR.AV.Hailo
  alias Membrane.RawVideo

  def_input_pad :input, accepted_format: %RawVideo{}
  def_output_pad :output, accepted_format: %RawVideo{}

  def_options hef_file: [
                spec: Path.t()
              ]

  @impl true
  def handle_init(_ctx, options) do
    {:ok, model} = Hailo.load(options.hef_file)
    state = %{model: model, width: nil, height: nil}
    Process.set_label(:object_detector)

    {[], state}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    state = %{
      state
      | width: stream_format.width,
        height: stream_format.height
    }

    {[forward: stream_format], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    {:ok, detections} =
      Hailo.infer(
        state.model,
        %{"yolov11l/input_layer1" => buffer.payload},
        Hailo.Parsers.YoloV8,
        key: "yolov11l/yolov8_nms_postprocess",
        classes: %{}
      )

    detections =
      detections
      |> Enum.filter(&(&1.class_id == 0 && &1.score >= 0.5))
      |> Hailo.Parsers.YoloV8.postprocess({state.height, state.width})

    {[buffer: {:output, %{buffer | metadata: Map.put(buffer.metadata, :detections, detections)}}],
     state}
  end
end
