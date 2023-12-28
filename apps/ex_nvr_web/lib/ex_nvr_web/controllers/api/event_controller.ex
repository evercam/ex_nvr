defmodule ExNVRWeb.API.EventController do
  use ExNVRWeb, :controller

  @events_types ["lpr"]

  action_fallback ExNVRWeb.API.FallbackController
  plug(:extract_device when action in [:create])
  plug(:ensure_type when action in [:create])

  alias Plug.Conn
  alias ExNVR.{Events, Devices}

  @spec create(Conn.t(), map()) :: {:error, any()} | Conn.t()
  def create(%Conn{body_params: params} = conn, _) do
    device = conn.assigns.device
    type = conn.assigns.type

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

  # Plugs
  defp extract_device(%Conn{query_params: params} = conn, _) do
    params
    |> Map.get("device_id")
    |> Devices.get()
    |> case do
      nil -> conn
      device -> assign(conn, :device, device)
    end
  end

  defp ensure_type(%Conn{query_params: params} = conn, _) do
    type = Map.get(params, "type")
    cond do
      Enum.member?(@events_types, type) ->
        conn
        |> Conn.assign(:type, String.to_atom(type))
      true ->
        conn
        |> Conn.resp(422, "")
        |> Conn.halt()
    end
  end
end
