defmodule ExNVRWeb.API.EventController do
  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController

  alias Plug.Conn
  alias ExNVR.Model.Device
  alias ExNVR.{Events, Devices}

  @spec create(Conn.t(), map()) :: {:error, Ecto.Changeset.t()} | Conn.t()
  def create(%Conn{body_params: body_params, query_params: query_params} = conn, _) do
    device_id = Map.get(query_params, "device_id", "")
    event_type = Map.get(query_params, "type", "")

    with %Device{} = device <- Devices.get(device_id),
          true <- event_type == "lpr",
          {:ok, params, plate_picture, full_picture} <- format_params(device, body_params),
          {:ok, _event} <- Events.create_lpr_event(params, plate_picture, full_picture)do
      send_resp(conn, 201, "")
    else
      error -> {:error, error}
    end
  end

  @spec index(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def index(%Conn{} = conn, params) do
    case Events.list_lpr_events(params) do
      {:ok, {events, meta}} ->
        meta =
          Map.take(meta, [
            :current_page,
            :page_size,
            :total_count,
            :total_pages
          ])

        events =
          events
          |> Enum.map(&serialize_event/1)

        conn
        |> put_status(200)
        |> json(%{meta: meta, data: events})

      {:error, meta} ->
        {:error, meta}
    end
  end

  defp format_params(%Device{id: id, timezone: timezone, vendor: "milesight"}, entry) do
    params = %{
      capture_time:
        entry
        |> Map.get("time", "")
        |> String.split(" ")
        |> parse_capture_time(timezone),
      plate_number: entry["plate"],
      direction: entry["direction"],
      list_type: entry["type"],
      confidence: entry["confidence"] && String.to_float(entry["confidence"]),
      vehicle_type: entry["vehicle_type"],
      vehicle_color: entry["vehicle_color"],
      plate_color: entry["plate_color"],
      bounding_box: %{
        x1: entry["coordinate_x1"],
        y1: entry["coordinate_y1"],
        x2: entry["coordinate_x2"],
        y2: entry["coordinate_y2"],
      },
      device_id: id
    }
    with {:ok, plate_picture} <- decode_image(params["plate_image"]),
         {:ok, full_picture} <- decode_image(params["full_image"]) do
      {:ok, params, plate_picture, full_picture}
    else
      _ -> {:error, "wrong plate or full image format"}
    end
  end

  defp format_params(_, _), do: %{}

  defp decode_image(nil), do: {:ok, nil}
  defp decode_image(image_base64), do: Base.decode64(image_base64)

  defp parse_capture_time([date, time], timezone) do
    DateTime.new!(
      Date.from_iso8601!(date),
      Time.from_iso8601!(time),
      timezone
    )
    |> DateTime.shift_zone!("Etc/UTC")
  end

  defp parse_capture_time(_, _), do: nil

  defp serialize_event(event) do
    event
    |> Map.drop([:__meta__, :device_name, :timezone])
    |> Map.put(:bounding_box, Map.from_struct(event.bounding_box))
  end
end
