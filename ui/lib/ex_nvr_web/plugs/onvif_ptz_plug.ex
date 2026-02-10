defmodule ExNVRWeb.Plug.OnvifPTZPlug do
  @moduledoc false

  require Logger
  alias ExOnvif.PTZ
  alias Plug.Conn
  import Plug.Conn

  def init(opts), do: opts

  def call(%Conn{} = conn, opts) do
    field_name = Keyword.get(opts, :field_name, "profile_token")
    profile_token = conn.path_params[field_name]
    device = conn.assigns.device

    with {:ok, onvif_device} <-
           ExNVR.Devices.Onvif.onvif_device(device),
         {:ok, status} <-
           PTZ.get_status(onvif_device, profile_token) do
      conn
      |> Conn.assign(:ptz_status, status)
      |> Conn.assign(:onvif_device, onvif_device)
    else
      {:error, _reason} ->
        body =
          Jason.encode!(%{
            error: "ptz_unavailable"
          })

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, body)
    end
  end
end
