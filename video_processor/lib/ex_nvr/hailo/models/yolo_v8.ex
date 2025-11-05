defmodule ExNVR.AV.Hailo.Parsers.YoloV8 do
  @moduledoc """
  Parser for the YoloV8 model with embedded NMS-pruning output.

  Fields: `N, ymin, xmin, ymax, xmax, score` for each class.
  """

  @behaviour ExNVR.AV.Hailo.OutputParser

  defmodule RawDetectedObject do
    @moduledoc """
    Raw detected object with the normalized coordinates in the padded image space.

    ((0, 0) is top-left corner and (1, 1) is bottom-right corner)
    """

    defstruct [:ymin, :ymax, :xmin, :xmax, :score, :class_name, :class_id]
  end

  defmodule DetectedObject do
    @moduledoc """
    Same fields as `RawDetectedObject` but with the coordinates mapped to the original image space.

    ((0, 0) is top-left corner and (height, width) is bottom-right corner)
    """
    defstruct [:ymin, :ymax, :xmin, :xmax, :score, :class_name, :class_id]
  end

  @impl ExNVR.AV.Hailo.OutputParser
  def parse(output_map, opts) when is_list(opts) do
    opts = Keyword.validate!(opts, [:classes, :key])
    key = Keyword.fetch!(opts, :key)
    classes = Keyword.fetch!(opts, :classes)

    floats_list = for <<x::float-32-little <- Map.fetch!(output_map, key)>>, do: x
    parse_list(floats_list, 0, classes, [])
  end

  @doc """
  Postprocesses the detected objects to return the objects in the original image space.

  ## Parameters

  - `detected_objects`: The list of `%RawDetectedObject{}` structs to process.
  - `input_shape`: The shape of the input image as {height, width}.
  - `padded_shape`: The shape of the padded image as {height, width}.

  ## Returns

  A list of `%DetectedObject{}` structs.
  """
  def postprocess(detected_objects, input_shape) do
    {input_height, input_width} = input_shape

    # pad to the larger square
    max_dim = max(input_height, input_width)

    # get the top and left padding
    padding_h = div(max_dim - input_height, 2)
    padding_w = div(max_dim - input_width, 2)

    Enum.map(detected_objects, fn %RawDetectedObject{} = object ->
      %DetectedObject{
        ymin: remap_coordinate(object.ymin, max_dim, padding_h, input_height),
        ymax: remap_coordinate(object.ymax, max_dim, padding_h, input_height),
        xmin: remap_coordinate(object.xmin, max_dim, padding_w, input_width),
        xmax: remap_coordinate(object.xmax, max_dim, padding_w, input_width),
        score: object.score,
        class_name: object.class_name,
        class_id: object.class_id
      }
    end)
  end

  defp remap_coordinate(coordinate, scale, padding, max_size) do
    padded_denorm = coordinate * scale
    unpadded_denorm = padded_denorm - padding

    unpadded_denorm
    |> round()
    |> max(0)
    |> min(max_size)
  end

  defp parse_list([], _, _, acc), do: {:ok, acc}

  defp parse_list([count | items], current_class, classes, acc) when count == 0 do
    parse_list(items, current_class + 1, classes, acc)
  end

  defp parse_list([count | items], current_class, classes, acc) do
    count = trunc(count)
    {class_items, rest} = Enum.split(items, count * 5)

    class_items =
      class_items
      |> Enum.chunk_every(5)
      |> Enum.map(fn [ymin, xmin, ymax, xmax, score] ->
        %RawDetectedObject{
          xmin: xmin,
          ymin: ymin,
          xmax: xmax,
          ymax: ymax,
          score: score,
          class_id: current_class,
          class_name: classes[current_class]
        }
      end)

    parse_list(rest, current_class + 1, classes, class_items ++ acc)
  end
end
