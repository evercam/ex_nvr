defmodule ExNVRWeb.PageController do
  use ExNVRWeb, :controller

  alias ExNVR.Devices

  def home(conn, _params) do
    redirect(conn, to: ~p"/dashboard")
  end

  def webrtc(conn, %{"device_id" => device_id}) do
    case Devices.get(device_id) do
      nil ->
        send_resp(conn, 404, "")

      device ->
        render(conn, :webrtc, device: device, layout: false)
    end
  end
end
