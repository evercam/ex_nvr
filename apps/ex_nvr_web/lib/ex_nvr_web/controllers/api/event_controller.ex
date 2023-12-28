defmodule ExNVRWeb.API.EventController do
  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController
  plug ExNVRWeb.Plug.Device, [field_name: "device_id"] when action in [:create]

  alias Plug.Conn
  alias ExNVR.Events

  @spec create(Plug.Conn.t(), map()) :: {:error, any()} | Plug.Conn.t()
  def create(%Conn{} = conn, %{"type" => type} = params) do
    device = conn.assigns.device

    with {:ok, event} <- Events.create(params, device, type) do
      event =
        event
        |> Map.drop([:__meta__, :device])
        |> Map.from_struct()

      conn
      |> put_status(201)
      |> json(%{event: event})
    end
  end
end
