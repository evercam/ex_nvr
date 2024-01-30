defmodule ExNVRWeb.API.RemoteStorageController do
  @moduledoc false

  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController

  plug :authorization_plug
  plug :remote_storage_plug, [field_name: "id"] when action in [:update, :show, :delete]

  import ExNVRWeb.Controller.Helpers
  import ExNVR.Authorization

  alias ExNVR.RemoteStorages
  alias ExNVR.Model.RemoteStorage
  alias Plug.Conn

  def authorization_plug(%Conn{} = conn, _opts) do
    user = conn.assigns.current_user

    case authorize(user, :remote_storage, :any) do
      :ok ->
        conn

      {:error, :unauthorized} ->
        conn
        |> forbidden()
        |> Conn.halt()
    end
  end

  def remote_storage_plug(%Conn{} = conn, opts) do
    field_name = Keyword.get(opts, :field_name, "remote_storage_id")
    remote_storage_id = conn.path_params[field_name]

    case RemoteStorages.get!(remote_storage_id) do
      %RemoteStorage{} = remote_storage ->
        Logger.metadata(remote_storage_id: remote_storage.id)
        Conn.assign(conn, :remote_storage_instance, remote_storage)

      nil ->
        conn
        |> not_found()
        |> Conn.halt()
    end
  end

  @spec create(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def create(%Conn{} = conn, params) do
    with {:ok, remote_storage} <- RemoteStorages.create(params) do
      conn
      |> put_status(201)
      |> render(:show, remote_storage_instance: remote_storage)
    end
  end

  @spec update(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def update(%Conn{} = conn, params) do
    remote_storage = conn.assigns.remote_storage_instance

    with {:ok, updated_remote_storage} <- RemoteStorages.update(remote_storage, params) do
      render(conn, :show, remote_storage_instance: updated_remote_storage)
    end
  end

  def delete(%Conn{} = conn, _params) do
    remote_storage_instance = conn.assigns.remote_storage_instance

    with {:ok, _deleted_remote_storage} <- RemoteStorages.delete(remote_storage_instance) do
      send_resp(conn, 204, "")
    end
  end

  @spec index(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def index(%Conn{} = conn, _params) do
    render(conn, :list, remote_storages: RemoteStorages.list())
  end

  @spec show(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def show(%Conn{} = conn, _params) do
    render(conn, :show, remote_storage_instance: conn.assigns.remote_storage_instance)
  end
end
