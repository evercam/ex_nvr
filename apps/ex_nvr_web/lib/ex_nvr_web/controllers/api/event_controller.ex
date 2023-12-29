defmodule ExNVRWeb.API.EventController do
  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController
  plug(:extract_device when action in [:create, :index])
  plug(:ensure_type when action in [:create, :index])

  alias Plug.Conn
  alias ExNVR.{Events, Devices}

  @spec create(Conn.t(), map()) :: {:error, Ecto.Changeset.t()} | Conn.t()
  def create(%Conn{body_params: params} = conn, _) do
    device = conn.assigns.device
    type = conn.assigns.type

    with {:ok, event} <- Events.create(params, device, type),
         event <- format_event(event) do
      conn
      |> put_status(201)
      |> json(%{event: event})
    end
  end

  @spec index(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def index(%Conn{} = conn, _params) do
    device = conn.assigns.device
    type = conn.assigns.type

    events =
      Events.list(device.id, type)
      |> Enum.map(&format_event/1)

    conn
    |> put_status(200)
    |> json(%{events: events})
  end

  defp format_event(event) do
    event
    |> Map.drop([:__meta__, :device])
    |> Map.from_struct()
  end

  # Plugs
  defp extract_device(%Conn{query_params: params} = conn, _) do
    params
    |> Map.get("device_id")
    |> Devices.get()
    |> case do
      nil ->
        conn
        |> Conn.resp(422, "")
        |> Conn.halt()

      device ->
        assign(conn, :device, device)
    end
  end

  defp ensure_type(%Conn{query_params: params} = conn, _) do
    case Map.get(params, "type") do
      nil ->
        conn
        |> Conn.resp(422, "")
        |> Conn.halt()

      type ->
        conn
        |> Conn.assign(:type, type)
    end
  end
end
