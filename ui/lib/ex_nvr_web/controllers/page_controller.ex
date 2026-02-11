defmodule ExNVRWeb.PageController do
  use ExNVRWeb, :controller

  plug ExNVRWeb.Plug.Device when action == :webrtc

  def home(conn, _params) do
    redirect(conn, to: ~p"/dashboard")
  end

  def webrtc(conn, params) do
    %{device: device, current_user: user} = conn.assigns
    token = Phoenix.Token.sign(conn, "user socket", user.id)

    conn
    |> delete_resp_header("x-frame-options")
    |> render(:webrtc,
      device: device,
      user_token: token,
      stream: parse_stream(params),
      layout: false
    )
  end

  defp parse_stream(params) do
    case params["stream"] do
      "low" -> :low
      _other -> :high
    end
  end
end
