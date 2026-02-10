defmodule ExNVRWeb.API.PTZController do
  use ExNVRWeb, :controller
  import ExNVRWeb.Controller.Helpers

  alias ExNVR.Devices.Onvif
  action_fallback ExNVRWeb.API.FallbackController

  plug ExNVRWeb.Plug.OnvifPTZPlug, [field_name: "profile_token"] when action in [:zoom]

  def zoom(
        conn,
        %{"device_id" => _device_id, "mode" => mode, "profile_token" => profile_token}
      ) do
    %{pan_tilt: %{x: x, y: y}, zoom: zoom} = conn.assigns.ptz_status.position

    onvif_device = conn.assigns.onvif_device

    new_zoom =
      case mode do
        "in" -> clamp(zoom + 0.1)
        "out" -> clamp(zoom - 0.1)
        _ -> 0.0
      end

    position = %{x: x, y: y, zoom: new_zoom}

    resp =
      Onvif.move_ptz(onvif_device, position)

    conn
    |> put_status(200)
    |> render(:show, position: position)
  end

  def move(
        conn,
        %{"device_id" => _device_id, "mode" => mode, "profile_token" => profile_token}
      ) do
    %{pan_tilt: %{x: x, y: y}, zoom: zoom} = conn.assigns.ptz_status.position

    onvif_device = conn.assigns.onvif_device

    new_position =
      case mode do
        "left" ->
          x =
            clamp(x - 0.1)

          %{x: x, y: y, zoom: zoom}

        "right" ->
          x = clamp(x + 0.1)

          %{x: x, y: y, zoom: zoom}

        "up" ->
          IO.inspect("up")
          y = clamp(y - 0.1)
          %{x: x, y: y, zoom: zoom}

        "down" ->
          y = clamp(y + 0.1)
          %{x: x, y: y, zoom: zoom}

        _ ->
          0.0
      end
      |> IO.inspect(label: "new position")

    Onvif.move_ptz(onvif_device, new_position)

    conn
    |> put_status(200)
    |> render(:show, position: new_position)
  end

  def stop(
        conn,
        %{"device_id" => _device_id, "mode" => mode, "profile_token" => profile_token} = _params
      ) do
    onvif_device = conn.assigns.onvif_device

    stop =
      case mode do
        "pan" ->
          ExOnvif.PTZ.Stop.new(profile_token, true, false)

        "zoom" ->
          ExOnvif.PTZ.Stop.new(profile_token, false, true)

        "both" ->
          ExOnvif.PTZ.Stop.new(profile_token, true, true)
      end

    ExOnvif.PTZ.stop(onvif_device, stop)
    |> case do
      :ok ->
        send_resp(conn, 200, "stopped")

      {:error, _reason} ->
        send_resp(conn, 404, "failed")
    end
  end

  def clamp(val, min \\ -1.0, max \\ 1.0) do
    val =
      val
      |> max(min)
      |> min(max)

    cond do
      val == min -> max
      val == max -> min
      true -> val
    end
  end
end
