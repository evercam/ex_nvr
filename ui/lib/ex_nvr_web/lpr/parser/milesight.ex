defmodule ExNVRWeb.LPR.Parser.Milesight do
  @moduledoc """
  An implementation of `ExNVRWeb.LPR.Parser` behaviour that parse milesight LPR event
  """

  @behaviour ExNVRWeb.LPR.Parser

  @impl true
  def parse(data, timezone) do
    event =
      %{
        plate_number: data["plate"],
        capture_time: parse_date(data["time"], timezone),
        direction: String.downcase(data["direction"]) |> map_direction(),
        list_type: String.downcase(data["type"]) |> map_list_type(),
        metadata: %{
          bounding_box: parse_bounding_box(data),
          confidence: parse_confidence(data["confidence"] || ""),
          vehicle_color: data["vehicle_color"],
          vehicle_type: data["vehicle_type"]
        }
      }

    {event, Base.decode64!(data["plate_image"])}
  end

  defp parse_date(iso_date, timezone) do
    iso_date
    |> NaiveDateTime.from_iso8601!()
    |> DateTime.from_naive!(timezone)
    |> DateTime.shift_zone!("UTC")
  end

  defp map_direction("approach"), do: :in
  defp map_direction("away"), do: :away
  defp map_direction(_other), do: :unknown

  defp map_list_type("white"), do: :white
  defp map_list_type("black"), do: :black
  defp map_list_type(_other), do: :other

  defp parse_bounding_box(data) do
    {w, h} =
      {String.to_integer(data["resolution_width"]), String.to_integer(data["resolution_height"])}

    {x1, y1, x2, y2} =
      {String.to_integer(data["coordinate_x1"]), String.to_integer(data["coordinate_y1"]),
       String.to_integer(data["coordinate_x2"]), String.to_integer(data["coordinate_y2"])}

    [x1 / w, y1 / h, x2 / w, y2 / h] |> Enum.map(&Float.round(&1, 2))
  end

  defp parse_confidence(confidence) do
    case Float.parse(confidence) do
      {value, ""} -> value
      _other -> nil
    end
  end
end
