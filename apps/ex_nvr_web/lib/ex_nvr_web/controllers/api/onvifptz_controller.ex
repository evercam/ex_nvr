defmodule ExNVRWeb.API.ONVIFPTZController do
  @moduledoc false

  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController

  alias ExNVR.Onvif
  alias Plug.Conn

  def status(conn, _params) do
    opts = get_onvif_access_info(conn)
    profile_token = opts[:profile_token]
    body = %{"ProfileToken" => profile_token}

    with {:ok, response} <- Onvif.call(opts[:url], :get_status, body, opts) do
      respond_default(response, conn, :get_status)
    end
  end

  def nodes(conn, _params) do
    opts = get_onvif_access_info(conn)
    profile_token = opts[:profile_token]
    body = %{"ProfileToken" => profile_token}

    with {:ok, response} <- Onvif.call(opts[:url], :get_nodes, body, opts) do
      respond_default(response, conn, :get_nodes)
    end
  end

  def configurations(conn, _params) do
    opts = get_onvif_access_info(conn)
    profile_token = opts[:profile_token]
    body = %{"ProfileToken" => profile_token}

    with {:ok, response} <-  Onvif.call(opts[:url], :get_configurations, body, opts) do
      respond_default(response, conn, :get_configurations)
    end
  end

  def presets(conn, _params) do
    opts = get_onvif_access_info(conn)
    profile_token = opts[:profile_token]
    body = %{"ProfileToken" => profile_token}

    with {:ok, response} <- Onvif.call(opts[:url], :get_presets, body, opts) do
      respond_default(response, conn, :get_presets)
    end
  end

  def stop(conn, _params) do
    opts = get_onvif_access_info(conn)
    profile_token = opts[:profile_token]
    body = %{"ProfileToken" => profile_token}

    with {:ok, response} <- Onvif.call(opts[:url], :stop, body, opts) do
      respond_default(response, conn, :stop)
    end
  end

  def home(conn, _params) do
    speed = []
    opts = get_onvif_access_info(conn)
    profile_token = opts[:profile_token]

    speed =
      case pan_tilt_zoom_vector(speed) do
        %{} -> %{}
        vector -> %{"Speed" => vector}
      end

    body = Map.merge(%{"ProfileToken" => profile_token}, speed)

    with {:ok, response} <- Onvif.call(opts[:url], :goto_home_position, body, opts) do
      respond_default(response, conn, :goto_home_position)
    end
  end

  def sethome(conn, _params) do
    opts = get_onvif_access_info(conn)
    profile_token = opts[:profile_token]
    body = %{"ProfileToken" => profile_token}

    with {:ok, response} <- Onvif.call(opts[:url], :set_home_position, body, opts) do
      respond_default(response, conn, :set_home_position)
    end
  end

  def gotopreset(conn, %{"preset_token" => token}) do
    speed = []
    opts = get_onvif_access_info(conn)
    profile_token = opts[:profile_token]
    body = %{"ProfileToken" => profile_token, "PresetToken" => token}

    speed =
      case pan_tilt_zoom_vector(speed) do
        %{} -> %{}
        vector -> %{"Speed" => vector}
      end

    body = Map.merge(body, speed)

    with {:ok, response} <- Onvif.call(opts[:url], :goto_preset, body, opts) do
      respond_default(response, conn, :goto_preset)
    end
  end

  def setpreset(conn, %{"preset_token" => token}) do
    opts = get_onvif_access_info(conn)
    profile_token = opts[:profile_token]
    body = %{"ProfileToken" => profile_token, "PresetToken" => token}

    with {:ok, response} <- Onvif.call(opts[:url], :set_preset, body, opts) do
      respond_default(response, conn, :set_preset)
    end
  end

  def createpreset(conn, %{"preset_name" => name}) do
    opts = get_onvif_access_info(conn)
    profile_token = opts[:profile_token]

    preset_name =
      case name do
        "" -> %{}
        _ -> %{"PresetName" => name}
      end

    body = Map.merge(%{"ProfileToken" => profile_token}, preset_name)

    with {:ok, response} <- Onvif.call(opts[:url], :set_preset, body, opts) do
      respond_default(response, conn, :set_preset)
    end
  end

  def continuousmove(conn, %{"direction" => direction}) do
    opts = get_onvif_access_info(conn)
    profile_token = opts[:profile_token]

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

    with {:ok, response} <- Onvif.call(opts[:url], :continuous_move, body, opts) do
      respond_default(response, conn, :continuous_move)
    end
  end

  def continuouszoom(conn, %{"mode" => mode}) do
    opts = get_onvif_access_info(conn)
    profile_token = opts[:profile_token]

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

    with {:ok, response} <- Onvif.call(opts[:url], :continuous_move, body, opts) do
      respond_default(response, conn, :continuous_move)
    end
  end

  def relativemove(conn, params) do
    opts = get_onvif_access_info(conn)
    speed = []
    profile_token = opts[:profile_token]

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

    with {:ok, response} <- Onvif.call(opts[:url], operation, body, opts) do
      respond_default(response, conn, operation)
    end
  end

  defp get_onvif_access_info(conn) do
    device = conn.assigns.device
    profile_token = "Profile_1"

    [_, ip_addr | _] = device.stream_config.stream_uri |> String.split(":")
    [_, ip_addr] = ip_addr |> String.split("//")
    http_port = "80"

    url = "#{ip_addr}:#{http_port}"

    [
      username: "admin", #device.credentials.username,
      password: "Mehcam4Mehcam", #device.credentials.password,
      auth: "#{device.credentials.username}:#{device.credentials.username}",
      profile_token: profile_token,
      url: "wg5.evercam.io:21339/onvif/ptz_service/" #url
    ]
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

  defp respond_default(response, conn, operation) do
    formatted_response = format_response(response, operation)
    conn
    |> json(formatted_response)
  end

  defp format_response(response, operation) do
    case operation do
      # :get_status -> format_status(response)
      # :get_nodes -> format_nodes(response)
      # :get_configurations -> format_configurations(response)
      :get_presets -> format_presets(response)

      # :stop -> format_stop(response)
      # :goto_home_position -> format_goto_home(response)
      # :goto_preset -> format_goto_preset(response)

      # :set_preset -> format_set_preset(response)
      # :remove_preset -> format_remove_preset(response)
      # :set_home_position -> format_goto_preset(response)
      # :relative_move -> format_set_preset(response)
      # :absolute_move -> format_remove_preset(response)
      # :continuous_move -> format_continuous_move(response)
    end
  end

  defp format_presets(%{GetPresetsResponse: presets}) do
    Keyword.values(presets)
      |> Enum.map(fn preset ->
        %{
          Name: preset[:Name],
          Token: preset[:token]
        }
      end)
  end
end
