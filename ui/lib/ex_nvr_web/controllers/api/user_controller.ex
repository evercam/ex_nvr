defmodule ExNVRWeb.API.UserController do
  @moduledoc false

  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController

  plug :authorization_plug
  plug :user_plug, [field_name: "id"] when action in [:update, :show, :delete]

  import ExNVRWeb.Controller.Helpers
  import ExNVR.Authorization

  alias ExNVR.Accounts
  alias Plug.Conn

  def authorization_plug(%Conn{} = conn, _opts) do
    user = conn.assigns.current_user

    case authorize(user, :user, :any) do
      :ok ->
        conn

      {:error, :unauthorized} ->
        conn
        |> forbidden()
        |> Conn.halt()
    end
  end

  def user_plug(%Conn{} = conn, opts) do
    field_name = Keyword.get(opts, :field_name, "user_id")
    user_id = conn.path_params[field_name]

    case Accounts.get_user(user_id) do
      %Accounts.User{} = user ->
        Logger.metadata(user_id: user.id)
        Conn.assign(conn, :user_instance, user)

      nil ->
        conn
        |> not_found()
        |> Conn.halt()
    end
  end

  @spec create(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def create(%Conn{} = conn, params) do
    with {:ok, created_user} <- Accounts.register_user(params) do
      conn
      |> put_status(201)
      |> render(:show, user_instance: created_user)
    end
  end

  @spec update(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def update(%Conn{} = conn, params) do
    user_instance = conn.assigns.user_instance

    with {:ok, updated_user} <- Accounts.update_user(user_instance, params) do
      render(conn, :show, user_instance: updated_user)
    end
  end

  def delete(%Conn{} = conn, _params) do
    user_instance = conn.assigns.user_instance

    with {:ok, _deleted_user} <- Accounts.delete_user(user_instance) do
      send_resp(conn, 204, "")
    end
  end

  @spec index(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def index(%Conn{} = conn, _params) do
    render(conn, :list, users: Accounts.list())
  end

  @spec show(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def show(%Conn{} = conn, _params) do
    render(conn, :show, user_instance: conn.assigns.user_instance)
  end
end
