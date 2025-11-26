defmodule ExNVR.Pipeline.Output.ObjectDetection do
  @moduledoc false

  use Membrane.Sink

  require Membrane.Logger

  import ExNVR.MediaUtils, only: [to_annexb: 1]

  alias ExNVR.AV.Decoder
  alias Membrane.{H264, H265}

  def_input_pad :input, accepted_format: any_of(H264, H265)

  def_options model: [
                type: :string,
                description: "Path to the object detection model file"
              ]

  @impl true
  def handle_init(_ctx, opts) do
    state = %{
      model: opts.model,
      pipeline: nil,
      decoder: nil,
      input_key: nil,
      output_key: nil
    }

    {[], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    case ExHailo.load(state.model) do
      {:ok, model} ->
        input_key = List.first(model.pipeline.input_vstream_infos).name
        out_key = List.first(model.pipeline.output_vstream_infos).name
        {[], %{state | pipeline: model, input_key: input_key, output_key: out_key}}

      {:error, reason} ->
        Membrane.Logger.error("Failed to load model: #{inspect(reason)}")
        {[], state}
    end
  end

  @impl true
  def handle_stream_format(:input, %format{}, _ctx, state) do
    codec =
      case format do
        H264 -> :h264
        H265 -> :hevc
      end

    decoder = Decoder.new(codec, out_width: 640, out_height: 640, out_format: :rgb24, pad?: true)

    {[], %{state | decoder: decoder}}
  end

  @impl true
  def handle_buffer(:input, _buffer, _ctx, %{pipeline: nil} = state) do
    {[], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, %{pipeline: pipeline} = state) do
    state.decoder
    |> Decoder.decode(to_annexb(buffer.payload))
    |> Enum.each(fn frame ->
      {:ok, detections} =
        ExHailo.infer(pipeline, %{state.input_key => frame.data}, ExHailo.Parsers.YoloV8,
          key: state.output_key,
          classes: %{0 => "person"}
        )

      detections = Enum.filter(detections, &(&1.class_id == 0 && &1.score > 0.5))

      if detections != [] do
        Membrane.Logger.info("Detected People: #{inspect(detections)}")
      end
    end)

    {[], state}
  end
end
