defmodule ExNVR.AV.ByteTracker do
  @moduledoc false

  alias ExNVR.AV.ByteTrack.NIF
  alias ExNVR.AV.Hailo.Parsers.YoloV8.DetectedObject

  @type tracker_ref :: reference() | nil

  @spec new() :: tracker_ref()
  def new do
    if NIF.loaded?(), do: NIF.create_tracker(), else: nil
  end

  @spec update(tracker_ref(), [DetectedObject.t()]) :: [map()]
  def update(nil, _boxes), do: []

  def update(ref, boxes) when is_reference(ref) and is_list(boxes) do
    boxes
    |> to_nif_inputs()
    |> NIF.update(ref)
    |> Enum.map(fn {x, y, w, h, id} ->
      %{x: x, y: y, width: w, height: h, id: id}
    end)
  end

  @doc false
  @spec to_nif_inputs([DetectedObject.t()]) :: [{float(), float(), float(), float(), integer(), float()}]
  def to_nif_inputs(boxes) do
    Enum.map(boxes, fn box ->
      width = max((box.xmax - box.xmin) * 1.0, 1.0)
      height = max((box.ymax - box.ymin) * 1.0, 1.0)
      {box.xmin * 1.0, box.ymin * 1.0, width, height, box.class_id, box.score}
    end)
  end
end
