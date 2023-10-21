defmodule ExNVRWeb.API.RecordingController do
  @moduledoc false
  use ExNVRWeb, :controller
  use Permit.Phoenix.Controller,
    authorization_module: ExNVR.Authorization,
    resource_module: ExNVR.Model.Recording

  action_fallback ExNVRWeb.API.FallbackController

  import ExNVRWeb.Controller.Helpers

  alias Ecto.Changeset
  alias ExNVR.Recordings

  @impl true
  def handle_unauthorized(_action, conn) do
    conn
    |> put_status(401)
    |> json(%{message: "You do not have permission to perform this action."})
  end

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

  @spec blob(Plug.Conn.t(), map) :: Plug.Conn.t()
  def blob(conn, %{"recording_id" => recording_filename}) do
    device = conn.assigns.device

    if content = Recordings.get_blob(device, recording_filename) do
      conn
      |> put_resp_content_type("video/mp4")
      |> put_resp_header("content-disposition", "attachment;filename=#{recording_filename}")
      |> send_resp(200, content)
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
