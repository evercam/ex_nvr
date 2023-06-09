defmodule ExNVRWeb.Plug.Device do
  @moduledoc """
  Get the device from database
  """

  import ExNVRWeb.Controller.Helpers

  alias ExNVR.{Devices, Model.Device}
  alias Plug.Conn

  def init(opts), do: opts

  def call(%Conn{} = conn, opts) do
    field_name = Keyword.get(opts, :field_name, "device_id")
    device_id = conn.path_params[field_name]

    case Devices.get(device_id) do
      %Device{} = device ->
        Conn.assign(conn, :device, device)

      nil ->
        conn
        |> not_found()
        |> Conn.halt()
    end
  end
end
