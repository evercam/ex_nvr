defmodule ExNVR.Pipeline.Output.ObjectDetection.Inferer do
  @moduledoc false

  use Membrane.Filter

  require Membrane.Logger

  alias ExNVR.AV.{ByteTracker, Hailo}
  alias Membrane.RawVideo

  @default_classes %{
    0 => "person", 1 => "bicycle", 2 => "car", 3 => "motorcycle",
    4 => "airplane", 5 => "bus", 6 => "train", 7 => "truck", 8 => "boat",
    9 => "traffic light", 10 => "fire hydrant", 11 => "stop sign",
    12 => "parking meter", 13 => "bench", 14 => "bird", 15 => "cat",
    16 => "dog", 17 => "horse", 18 => "sheep", 19 => "cow", 20 => "elephant",
    21 => "bear", 22 => "zebra", 23 => "giraffe", 24 => "backpack",
    25 => "umbrella", 26 => "handbag", 27 => "tie", 28 => "suitcase",
    29 => "frisbee", 30 => "skis", 31 => "snowboard", 32 => "sports ball",
    33 => "kite", 34 => "baseball bat", 35 => "baseball glove",
    36 => "skateboard", 37 => "surfboard", 38 => "tennis racket",
    39 => "bottle", 40 => "wine glass", 41 => "cup", 42 => "fork",
    43 => "knife", 44 => "spoon", 45 => "bowl", 46 => "banana", 47 => "apple",
    48 => "sandwich", 49 => "orange", 50 => "broccoli", 51 => "carrot",
    52 => "hot dog", 53 => "pizza", 54 => "donut", 55 => "cake", 56 => "chair",
    57 => "couch", 58 => "potted plant", 59 => "bed", 60 => "dining table",
    61 => "toilet", 62 => "tv", 63 => "laptop", 64 => "mouse", 65 => "remote",
    66 => "keyboard", 67 => "cell phone", 68 => "microwave", 69 => "oven",
    70 => "toaster", 71 => "sink", 72 => "refrigerator", 73 => "book",
    74 => "clock", 75 => "vase", 76 => "scissors", 77 => "teddy bear",
    78 => "hair drier", 79 => "toothbrush"
  }

  def_input_pad :input, accepted_format: %RawVideo{}
  def_output_pad :output, accepted_format: %RawVideo{}

  def_options hef_file: [
                spec: Path.t()
              ],
              classes: [
                spec: %{non_neg_integer() => String.t()} | nil,
                default: nil
              ]

  @impl true
  def handle_init(_ctx, options) do
    state = %{
      hef_file: options.hef_file,
      classes: options.classes || load_classes() || @default_classes,
      model: nil,
      width: nil,
      height: nil,
      tracker: nil,
      input_layer: nil,
      output_layer: nil,
      score_threshold: parse_score_threshold(System.get_env("EXNVR_OBJECT_DETECTION_SCORE_THRESHOLD"))
    }

    {[], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    case Hailo.load(state.hef_file) do
      {:ok, model} ->
        input_layer = select_input_layer(model, System.get_env("EXNVR_OBJECT_DETECTION_INPUT_LAYER"))
        output_layer = select_output_layer(model, System.get_env("EXNVR_OBJECT_DETECTION_OUTPUT_LAYER"))

        Membrane.Logger.info(
          "Hailo model loaded, input=#{input_layer} output=#{output_layer}"
        )

        {[],
         %{
           state
           | model: model,
             tracker: ByteTracker.new(),
             input_layer: input_layer,
             output_layer: output_layer
         }}

      {:error, reason} ->
        Membrane.Logger.error("Failed to load Hailo model: #{inspect(reason)}")
        {[], state}
    end
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    {[forward: stream_format],
     %{state | width: stream_format.width, height: stream_format.height}}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, %{model: nil} = state) do
    {[buffer: {:output, buffer}], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    frame_width = Map.get(buffer.metadata, :frame_width, state.width)
    frame_height = Map.get(buffer.metadata, :frame_height, state.height)

    detections =
      case Hailo.infer(
             state.model,
             %{state.input_layer => buffer.payload},
             Hailo.Parsers.YoloV8,
             key: state.output_layer,
             classes: state.classes
           ) do
        {:ok, detections} ->
          detections

        {:error, reason} ->
          Membrane.Logger.warning("Hailo infer failed: #{inspect(reason)}")
          []
      end

    detections_post =
      detections
      |> Enum.filter(&(&1.score >= state.score_threshold))
      |> Hailo.Parsers.YoloV8.postprocess({frame_height, frame_width})

    tracks =
      state.tracker
      |> ByteTracker.update(detections_post)
      |> attach_track_classes(detections_post)

    metadata =
      buffer.metadata
      |> Map.put(:frame_width, frame_width)
      |> Map.put(:frame_height, frame_height)
      |> Map.put(:detections, detections_post)
      |> Map.put(:tracks, tracks)

    {[buffer: {:output, %{buffer | metadata: metadata}}], state}
  end

  defp attach_track_classes(tracks, detections) do
    Enum.map(tracks, fn track ->
      {class_id, class_name, score} = best_detection_for_track(track, detections)

      Map.merge(track, %{
        class_id: class_id,
        class_name: class_name,
        score: score
      })
    end)
  end

  defp select_input_layer(model, input_layer_override) do
    input_layer_override ||
      (model.pipeline.input_vstream_infos
       |> List.first()
       |> Map.fetch!(:name))
  end

  defp select_output_layer(model, output_layer_override) do
    output_layer_override ||
      (model.pipeline.output_vstream_infos
       |> Enum.find_value(fn info ->
         name = Map.fetch!(info, :name)
         if String.contains?(name, "nms"), do: name, else: nil
       end) ||
         model.pipeline.output_vstream_infos
         |> List.first()
         |> Map.fetch!(:name))
  end

  defp parse_score_threshold(nil), do: 0.35

  defp parse_score_threshold(value) do
    case Float.parse(value) do
      {parsed, _rest} -> parsed
      :error -> 0.35
    end
  end

  defp best_detection_for_track(track, detections) do
    track_box = {track.x, track.y, track.x + track.width, track.y + track.height}

    detections
    |> Enum.map(fn det ->
      score = iou(track_box, {det.xmin, det.ymin, det.xmax, det.ymax})
      {score, det}
    end)
    |> Enum.max_by(fn {score, _det} -> score end, fn -> {0.0, nil} end)
    |> case do
      {score, det} when not is_nil(det) and score > 0.1 ->
        {det.class_id, det.class_name, det.score}

      _other ->
        {nil, "unknown", nil}
    end
  end

  defp load_classes do
    case System.get_env("EXNVR_OBJECT_DETECTION_CLASSES_FILE") do
      nil ->
        nil

      path ->
        with {:ok, content} <- File.read(path),
             {:ok, classes} <- decode_classes(content) do
          classes
        else
          {:error, reason} ->
            Membrane.Logger.warning("Failed to load detection classes: #{inspect(reason)}")
            nil
        end
    end
  end

  defp decode_classes(content) do
    case Jason.decode(content) do
      {:ok, list} when is_list(list) ->
        {:ok, list |> Enum.with_index() |> Map.new(fn {name, idx} -> {idx, name} end)}

      {:ok, map} when is_map(map) ->
        classes =
          map
          |> Enum.map(fn {key, value} ->
            case Integer.parse(to_string(key)) do
              {idx, ""} when is_binary(value) -> {:ok, {idx, value}}
              _other -> {:error, {key, value}}
            end
          end)

        if Enum.all?(classes, &match?({:ok, _value}, &1)) do
          {:ok, Map.new(classes, fn {:ok, value} -> value end)}
        else
          {:error, :invalid_classes_map}
        end

      {:ok, _other} ->
        {:error, :invalid_classes_file}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp iou({ax1, ay1, ax2, ay2}, {bx1, by1, bx2, by2}) do
    inter_w = max(0.0, min(ax2, bx2) - max(ax1, bx1))
    inter_h = max(0.0, min(ay2, by2) - max(ay1, by1))
    inter_area = inter_w * inter_h

    area_a = max(0.0, ax2 - ax1) * max(0.0, ay2 - ay1)
    area_b = max(0.0, bx2 - bx1) * max(0.0, by2 - by1)
    union = area_a + area_b - inter_area

    if union > 0.0, do: inter_area / union, else: 0.0
  end
end
