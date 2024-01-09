defmodule ExNVRWeb.ONVIFPTZController do
  @moduledoc false

  use ExNVRWeb, :controller
  alias ExNVR.Onvif

  def status(conn, _params) do
    opts = get_onvif_access_info(conn)
    profile_token = opts["profile_token"]
    body = %{"ProfileToken" => profile_token}

    Onvif.call(opts["url"], :get_status, body, opts)

  end

  def nodes(conn, _params) do
    opts = get_onvif_access_info(conn)
    profile_token = opts["profile_token"]
    body = %{"ProfileToken" => profile_token}

    Onvif.call(opts["url"], :get_nodes, body, opts)

  end

  def configurations(conn, _params) do
    opts = get_onvif_access_info(conn)
    profile_token = opts["profile_token"]
    body = %{"ProfileToken" => profile_token}

    Onvif.call(opts["url"], :get_configurations, body, opts)

  end

  def presets(conn, _params) do
    opts = get_onvif_access_info(conn)
    profile_token = opts["profile_token"]
    body = %{"ProfileToken" => profile_token}

    Onvif.call(opts["url"], :get_presets, body, opts)

  end

  def stop(conn, _params) do
    opts = get_onvif_access_info(conn)
    profile_token = opts["profile_token"]
    body = %{"ProfileToken" => profile_token}

    Onvif.call(opts["url"], :stop, body, opts)

  end

  def home(conn, _params) do
    speed = []
    opts = get_onvif_access_info(conn)
    profile_token = opts["profile_token"]

    speed =
      case pan_tilt_zoom_vector(speed) do
        %{} -> %{}
        vector -> %{"Speed" => vector}
      end

    body = Map.merge(%{"ProfileToken" => profile_token}, speed)

    Onvif.call(opts["url"], :goto_home_position, body, opts)

  end

  def sethome(conn, _params) do
    opts = get_onvif_access_info(conn)
    profile_token = opts["profile_token"]
    body = %{"ProfileToken" => profile_token}

    Onvif.call(opts["url"], :set_home_position, body, opts)

  end

  def gotopreset(conn, %{"preset_token" => token}) do
    speed = []
    opts = get_onvif_access_info(conn)
    profile_token = opts["profile_token"]
    body = %{"ProfileToken" => profile_token, "PresetToken" => token}

    speed =
      case pan_tilt_zoom_vector(speed) do
        %{} -> %{}
        vector -> %{"Speed" => vector}
      end

    body = Map.merge(body, speed)

    Onvif.call(opts["url"], :goto_preset, body, opts)

  end

  def setpreset(conn, %{"preset_token" => token}) do
    opts = get_onvif_access_info(conn)
    profile_token = opts["profile_token"]
    body = %{"ProfileToken" => profile_token, "PresetToken" => token}

    Onvif.call(opts["url"], :set_preset, body, opts)

  end

  def createpreset(conn, %{"preset_name" => name}) do
    opts = get_onvif_access_info(conn)
    profile_token = opts["profile_token"]

    preset_name =
      case name do
        "" -> %{}
        _ -> %{"PresetName" => name}
      end

    body = Map.merge(%{"ProfileToken" => profile_token}, preset_name)

    Onvif.call(opts["url"], :set_preset, body, opts)

  end

  def continuousmove(conn, %{"direction" => direction}) do
    opts = get_onvif_access_info(conn)
    profile_token = opts["profile_token"]

    velocity =
      case direction do
        "left" -> [x: -0.4, y: 0.0]
        "right" -> [x: 0.4, y: 0.0]
        "up" -> [x: 0.0, y: 0.4]
        "down" -> [x: 0.0, y: -0.4]
        _ -> [x: 0.0, y: 0.0]
      end

    move_params =
      case pan_tilt_zoom_vector(velocity) do
        %{} -> %{}
        vector -> %{"Velocity" => vector}
      end

    body = Map.merge(%{"ProfileToken" => profile_token}, move_params)

    Onvif.call(opts["url"], :continuous_move, body, opts)

  end

  def continuouszoom(conn, %{"mode" => mode}) do
    opts = get_onvif_access_info(conn)
    profile_token = opts["profile_token"]

    velocity =
      case mode do
        "in" -> [zoom: 0.03]
        "out" -> [zoom: -0.03]
        _ -> [zoom: 0.0]
      end

    zoom_params =
      case pan_tilt_zoom_vector(velocity) do
        %{} -> %{}
        vector -> %{"Velocity" => vector}
      end

    body = Map.merge(%{"ProfileToken" => profile_token}, zoom_params)

    Onvif.call(opts["url"], :continuous_move, body, opts)

  end

  def relativemove(conn, params) do
    opts = get_onvif_access_info(conn)
    speed = []
    profile_token = opts["profile_token"]

    left = Map.get(params, "left", "0") |> String.to_integer()
    right = Map.get(params, "right", "0") |> String.to_integer()
    up = Map.get(params, "up", "0") |> String.to_integer()
    down = Map.get(params, "down", "0") |> String.to_integer()
    zoom = Map.get(params, "zoom", "0") |> String.to_integer()
    x = if right > left, do: right, else: -left
    y = if down > up, do: -down, else: up

    operation =
      if String.equivalent?(profile_token, "Profile_1"),
        do: :relative_move,
        else: :absolute_move

    speed =
      case pan_tilt_zoom_vector(speed) do
        %{} -> %{}
        vector -> %{"Speed" => vector}
      end

    translation = %{
      "Translation" => pan_tilt_zoom_vector(x: x / 100.0, y: y / 100.0, zoom: zoom / 100.0)
    }

    move_params = Map.merge(speed, translation)
    body = Map.merge(%{"ProfileToken" => profile_token}, move_params)

    Onvif.call(opts["url"], operation, body, opts)

  end

  defp get_onvif_access_info(conn) do
    device = conn.assigns.device
    profile_token = "Profile_1"

    [_, ip_addr | _] = device.stream_config.stream_uri |> String.split(":")
    [_, ip_addr] = ip_addr |> String.split("//")
    http_port = "80"

    url = "#{ip_addr}:#{http_port}"

    %{
      "username" => device.credentials.username,
      "password" => device.credentials.password,
      "auth" => "#{device.credentials.username}:#{device.credentials.username}",
      "profile_token" => profile_token,
      "url" => url
    }
  end

  defp pan_tilt_zoom_vector(vector) do
    pan_tilt =
      case {vector[:x], vector[:y]} do
        {nil, _} -> %{}
        {_, nil} -> %{}
        {x, y} -> %{"PanTilt" => %{"x" => x, "y" => y}}
      end

    zoom =
      case vector[:zoom] do
        nil -> %{}
        zoom -> %{"Zoom" => %{"x" => zoom}}
      end

    Map.merge(pan_tilt, zoom)
  end
end
