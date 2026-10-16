defmodule ExNVRWeb.PageController do
  use ExNVRWeb, :controller

  plug ExNVRWeb.Plug.Device when action in [:webrtc]

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

  # The generic events page was merged into the activity page, keep the old links working.
  def generic_events(conn, params) do
    tab = if params["tab"] == "webhook", do: "webhook", else: "system"
    redirect(conn, to: ~p"/activity?#{Map.put(params, "tab", tab)}")
  end

  defp parse_stream(params) do
    case params["stream"] do
      "low" -> :low
      _other -> :high
    end
  end
end
