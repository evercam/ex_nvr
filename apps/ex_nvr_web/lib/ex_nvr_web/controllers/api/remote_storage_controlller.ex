defmodule ExNVRWeb.API.RemoteStorageController do
  @moduledoc false

  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController

  plug :authorization_plug
  plug :remote_storage_plug when action in [:update, :show, :delete]

  import ExNVRWeb.Controller.Helpers
  import ExNVR.Authorization

  alias ExNVR.RemoteStorages
  alias ExNVR.RemoteStorage
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

  def remote_storage_plug(%Conn{} = conn, _opts) do
    remote_storage_id = conn.path_params["id"]

    case RemoteStorages.get(remote_storage_id) do
      %RemoteStorage{} = remote_storage ->
        Conn.assign(conn, :remote_storage, remote_storage)

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
      |> render(:show, remote_storage: remote_storage)
    end
  end

  @spec update(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def update(%Conn{} = conn, params) do
    remote_storage = conn.assigns.remote_storage

    with {:ok, updated_remote_storage} <- RemoteStorages.update(remote_storage, params) do
      render(conn, :show, remote_storage: updated_remote_storage)
    end
  end

  def delete(%Conn{} = conn, _params) do
    remote_storage = conn.assigns.remote_storage

    with :ok <- RemoteStorages.delete(remote_storage) do
      send_resp(conn, 204, "")
    end
  end

  @spec index(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def index(%Conn{} = conn, _params) do
    render(conn, :list, remote_storages: RemoteStorages.list())
  end

  @spec show(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def show(%Conn{} = conn, _params) do
    render(conn, :show, remote_storage: conn.assigns.remote_storage)
  end
end
