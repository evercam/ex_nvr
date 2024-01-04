defmodule ExNVRWeb.Plug.User do
  @moduledoc """
  Loads the user instance from database
  """

  import ExNVRWeb.Controller.Helpers

  require Logger

  alias ExNVR.Accounts
  alias Plug.Conn

  def init(opts), do: opts

  def call(%Conn{} = conn, opts) do
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
end

defmodule ExNVRWeb.Plug.Authorization do
  @moduledoc """
  Check if user is authorized.
  """

  import ExNVRWeb.Controller.Helpers
  import ExNVR.Authorization

  alias Plug.Conn

  def init(opts), do: opts

  def call(%Conn{} = conn, _opts) do
    user = conn.assigns.current_user

    case authorize(user, :user, :any) do
      :ok ->
        conn

      {:error, :unauthorized} ->
        conn
        |> unauthorized()
        |> Conn.halt()
    end
  end
end

defmodule ExNVRWeb.API.UserController do
  @moduledoc false

  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController

  plug ExNVRWeb.Plug.User, [field_name: "id"] when action in [:update, :show, :delete]
  plug ExNVRWeb.Plug.Authorization

  alias ExNVR.Accounts
  alias Plug.Conn

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
