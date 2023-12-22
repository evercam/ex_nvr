defmodule ExNVRWeb.API.UserController do
  @moduledoc false

  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController

  plug ExNVRWeb.Plug.User, [field_name: "id"] when action in [:update, :show, :delete]

  import ExNVR.Authorization

  alias ExNVR.Accounts
  alias Plug.Conn

  @spec create(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def create(%Conn{} = conn, params) do
    user = conn.assigns.current_user

    with :ok <- authorize(user, :user, :create),
         {:ok, created_user} <- Accounts.register_user(params) do
      conn
      |> put_status(201)
      |> render(:show, user_instance: created_user)
    end
  end

  @spec update(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def update(%Conn{} = conn, params) do
    user_instance = conn.assigns.user_instance
    user = conn.assigns.current_user

    with :ok <- authorize(user, :user, :update),
         {:ok, updated_user} <- Accounts.update_user(user_instance, params) do
      render(conn, :show, user_instance: updated_user)
    end
  end

  def delete(%Conn{} = conn, _params) do
    user_instance = conn.assigns.user_instance
    user = conn.assigns.current_user

    with :ok <- authorize(user, :user, :delete),
         {:ok, _deleted_user} <- Accounts.delete_user(user_instance) do
      send_resp(conn, 204, "")
    end
  end

  @spec index(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def index(%Conn{} = conn, _params) do
    user = conn.assigns.current_user

    with :ok <- authorize(user, :user, :read),
         do: render(conn, :list, users: Accounts.list())
  end

  @spec show(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def show(%Conn{} = conn, _params) do
    user = conn.assigns.current_user

    with :ok <- authorize(user, :user, :read),
         do: render(conn, :show, user_instance: conn.assigns.user_instance)
  end
end
