defmodule ExNVRWeb.API.PTZController do
  use ExNVRWeb, :controller

  alias ExNVR.Devices.Onvif
  alias ExOnvif.PTZ
  action_fallback ExNVRWeb.API.FallbackController

  plug ExNVRWeb.Plug.OnvifPTZPlug, [field_name: "profile_token"] when action in [:zoom]

  def zoom(
        conn,
        %{"device_id" => _device_id, "mode" => mode, "profile_token" => _profile_token}
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

    Onvif.move_ptz(onvif_device, position)

    conn
    |> put_status(200)
    |> render(:show, position: position)
  end

  def move(
        conn,
        %{"device_id" => _device_id, "mode" => mode, "profile_token" => _profile_token}
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
          y = clamp(y - 0.1)
          %{x: x, y: y, zoom: zoom}

        "down" ->
          y = clamp(y + 0.1)
          %{x: x, y: y, zoom: zoom}

        _ ->
          0.0
      end

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

  def status(conn, _params) do
    ptz_status = conn.assigns.ptz_status

    conn
    |> put_status(200)
    |> render(:show, position: ptz_status.position)
  end

  def continuous_move(
        conn,
        %{"x" => x, "y" => y, "zoom" => zoom, "profile_token" => profile_token} = _params
      ) do
    vector = PTZ.Vector.new(x, y, zoom)

    move = ExOnvif.PTZ.ContinuousMove.new(profile_token, vector)

    ExOnvif.PTZ.continuous_move(conn.assigns.onvif_device, move)
    |> case do
      :ok ->
        send_resp(conn, 200, "moving")

      {:error, _reason} ->
        send_resp(conn, 404, "failed to move")
    end
  end

  def get_nodes(conn, _params) do
    onvif_device = conn.assigns.onvif_device

    case ExOnvif.PTZ.get_nodes(onvif_device) do
      {:ok, nodes} ->
        nodes = deep_to_map(nodes)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(nodes))

      {:error, _reason} ->
        send_resp(conn, 404, "failed to get nodes")
    end
  end

  def get_node_info(conn, %{"node_token" => node_token} = _params) do
    onvif_device = conn.assigns.onvif_device

    case ExOnvif.PTZ.get_node(onvif_device, node_token) do
      {:ok, node_info} ->
        node_info = deep_to_map(node_info)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(node_info))

      {:error, _reason} ->
        send_resp(conn, 404, "failed to get node info")
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

  defp deep_to_map(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.map(fn {k, v} -> {k, deep_to_map(v)} end)
    |> Enum.into(%{})
  end

  defp deep_to_map(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {k, deep_to_map(v)} end)
    |> Enum.into(%{})
  end

  defp deep_to_map(list) when is_list(list) do
    Enum.map(list, &deep_to_map/1)
  end

  defp deep_to_map(value), do: value
end
