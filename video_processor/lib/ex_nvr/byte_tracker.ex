defmodule ExNVR.AV.ByteTracker do
  @moduledoc false

  alias ExNVR.AV.ByteTrack.NIF
  alias ExNVR.AV.Hailo.Parsers.YoloV8.DetectedObject

  @spec new() :: reference()
  def new() do
    NIF.create_tracker()
  end

  @spec update([DetectedObject.t()], reference()) :: [map()]
  def update(boxes, ref) do
    boxes
    |> Enum.map(fn box ->
      {box.xmin, box.ymin, box.xmax, box.ymax, box.class_id, box.score}
    end)
    |> NIF.update(ref)
    |> Enum.map(fn {x, y, w, h, id} ->
      %{x: x, y: y, width: w, height: h, id: id}
    end)
  end
end
