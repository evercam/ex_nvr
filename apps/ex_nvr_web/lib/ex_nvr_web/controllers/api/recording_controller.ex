defmodule ExNVRWeb.API.RecordingController do
  @moduledoc false

  use ExNVRWeb, :controller

  import ExNVRWeb.Controller.Helpers

  plug ExNVRWeb.Plug.Device

  alias ExNVR.Recordings

  @spec blob(Plug.Conn.t(), map) :: Plug.Conn.t()
  def blob(conn, %{"recording_id" => recording_filename}) do
    device = conn.assigns.device

    if content = Recordings.get_blob(device, recording_filename) do
      conn
      |> put_resp_content_type("video/mp4")
      |> put_resp_header("content-disposition", "inline")
      |> send_resp(200, content)
    else
      not_found(conn)
    end
  end
end
