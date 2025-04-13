defmodule ExNVRWeb.API.EventController do
  use ExNVRWeb, :controller

  action_fallback(ExNVRWeb.API.FallbackController)

  alias Ecto.Changeset
  alias ExNVR.Events
  alias ExNVR.Model.Device
  alias Plug.Conn

  @spec create(Conn.t(), map()) :: Conn.t()
  def create(conn, params) do
    device = conn.assigns.device
    event_params = Map.put(params, "metadata", conn.body_params)

    with {:ok, _event} <- Events.create_event(device, event_params) do
      send_resp(conn, 201, "")
    end
  end

  @spec create_lpr(Conn.t(), map()) :: {:error, term()} | Conn.t()
  def create_lpr(conn, params) do
    device = conn.assigns.device

    with {:ok, {event, plate_image}} <- get_lpr_event(device, params),
         {:ok, _event} <- Events.create_lpr_event(device, event, plate_image) do
      send_resp(conn, 201, "")
    end
  end

  @spec lpr(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def lpr(%Conn{} = conn, params) do
    with {:ok, event_params} <- validate_get_events_req(params),
         {:ok, {events, meta}} <-
           Events.list_lpr_events(params, include_plate_image: event_params.include_plate_image) do
      meta =
        Map.take(meta, [
          :current_page,
          :page_size,
          :total_count,
          :total_pages
        ])

      conn
      |> put_status(200)
      |> json(%{meta: meta, data: events})
    end
  end

  @spec events(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def events(%Conn{} = conn, params) do
    with {:ok, {events, meta}} <- Events.list_events(params) do
      meta =
        Map.take(meta, [
          :current_page,
          :page_size,
          :total_count,
          :total_pages
        ])

      conn
      |> put_status(200)
      |> json(%{meta: meta, data: events})
    end
  end

  defp get_lpr_event(device, params) do
    case Device.vendor(device) do
      :milesight -> {:ok, ExNVRWeb.LPR.Parser.Milesight.parse(params, device.timezone)}
      _other -> {:error, :not_found}
    end
  end

  defp validate_get_events_req(params) do
    types = %{
      include_plate_image: :boolean
    }

    {%{include_plate_image: false}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.apply_action(:create)
  end
end
