defmodule ExNVRWeb.API.DiskController do
  use ExNVRWeb, :controller

  alias Plug.Conn
  alias ExNVR.SystemInformation.Disks

  def list(%Conn{} = conn, _params) do
    conn
    |> put_status(200)
    |> json(%{disks: Disks.list()})
  end
end
