defmodule ExNVRWeb.API.EventController do
  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController

  alias ExNVR.Events
  alias ExNVR.Model.Device
  alias Plug.Conn

  @spec create(Conn.t(), map()) :: {:error, term()} | Conn.t()
  def create(conn, params) do
    device = conn.assigns.device

    with :ok <- check_event_type(params["event_type"]),
         {:ok, {event, plate_image}} <- get_event(device, params),
         {:ok, _event} <- Events.create_lpr_event(device, event, plate_image) do
      send_resp(conn, 201, "")
    end
  end

  @spec index(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def index(%Conn{} = conn, params) do
    case Events.list_lpr_events(params) do
      {:ok, {events, meta}} ->
        meta =
          Map.take(meta, [
            :current_page,
            :page_size,
            :total_count,
            :total_pages
          ])

        events =
          events
          |> Enum.map(&serialize_event/1)

        conn
        |> put_status(200)
        |> json(%{meta: meta, data: events})

      {:error, meta} ->
        {:error, meta}
    end
  end

  defp get_event(device, params) do
    case Device.vendor(device) do
      :milesight -> {:ok, ExNVRWeb.LPR.Parser.Milesight.parse(params, device.timezone)}
      _other -> {:error, :not_found}
    end
  end

  defp serialize_event(event) do
    event
    |> Map.drop([:__meta__, :device_name, :timezone])
    |> Map.put(:bounding_box, Map.from_struct(event.bounding_box))
  end

  defp check_event_type("lpr"), do: :ok
  defp check_event_type(_), do: {:error, :not_found}
end
