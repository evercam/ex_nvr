defmodule ExNVR.AV.ByteTracker do
  @moduledoc false

  alias ExNVR.AV.ByteTrack.NIF
  alias ExNVR.AV.Hailo.Parsers.YoloV8.DetectedObject

  @spec new_tracker() :: reference()
  def new_tracker() do
    NIF.create_tracker()
  end

  @spec update(reference(), [DetectedObject.t()]) :: [map()]
  def update(ref, boxes) do
    ref
    |> NIF.update(boxes)
    |> Enum.map(fn {x, y, w, h, id} ->
      %{x: x, y: y, width: w, height: h, id: id}
    end)
  end
end
