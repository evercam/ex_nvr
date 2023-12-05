defmodule ExNVRWeb.API.RecordingController do
  @moduledoc false
  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController

  import ExNVRWeb.Controller.Helpers

  alias Ecto.Changeset
  alias ExNVR.Recordings

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, Changeset.t()}
  def index(conn, params) do
    device = conn.assigns.device

    with {:ok, params} <- validate_index_req_params(params) do
      params
      |> Map.put(:device_id, device.id)
      |> Recordings.list_runs()
      |> Enum.map(&Map.take(&1, [:start_date, :end_date, :active]))
      |> then(&json(conn, &1))
    end
  end

  @spec chunks(Plug.Conn.t(), map) :: Plug.Conn.t()
  def chunks(conn, params) do
    case Recordings.list(params) do
      {:ok, {recordings, meta}} ->
        meta =
          Map.take(meta, [
            :current_page,
            :page_size,
            :total_count,
            :total_pages
          ])

        recordings = Enum.map(recordings, &Map.drop(&1, [:device_name, :timezone]))

        json(conn, %{meta: meta, data: recordings})

      {:error, meta} ->
        {:error, meta}
    end
  end

  @spec blob(Plug.Conn.t(), map) :: Plug.Conn.t()
  def blob(conn, %{"recording_id" => recording_filename}) do
    device = conn.assigns.device

    if recording = Recordings.get(device, recording_filename) do
      send_download(conn, {:file, Recordings.recording_path(device, recording)},
        filename: recording_filename,
        content_type: "video/mp4"
      )
    else
      not_found(conn)
    end
  end

  defp validate_index_req_params(params) do
    types = %{start_date: :utc_datetime_usec}

    {%{}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.apply_action(:create)
  end
end
