defmodule ExNVRWeb.API.WebhookTokenController do
  @moduledoc false

  use ExNVRWeb, :controller

  import ExNVR.Authorization

  alias ExNVR.Accounts
  alias Plug.Conn

  action_fallback ExNVRWeb.API.FallbackController

  @spec show(Conn.t(), map()) :: Conn.t() | {:error, atom()}
  def show(%Conn{} = conn, _params) do
    user = conn.assigns.current_user

    with :ok <- authorize(user, :webhook, :read) do
      case Accounts.get_webhook_token(user) do
        nil -> {:error, :not_found}
        webhook_token -> render(conn, :show, webhook_token: webhook_token)
      end
    end
  end

  @spec create(Conn.t(), map()) :: Conn.t() | {:error, atom()}
  def create(%Conn{} = conn, _params) do
    user = conn.assigns.current_user

    with :ok <- authorize(user, :webhook, :create) do
      case Accounts.get_webhook_token(user) do
        nil ->
          Accounts.generate_webhook_token(user)

          conn
          |> put_status(201)
          |> render(:show, webhook_token: Accounts.get_webhook_token(user))

        webhook_token ->
          render(conn, :show, webhook_token: webhook_token)
      end
    end
  end

  @spec delete(Conn.t(), map()) :: Conn.t() | {:error, atom()}
  def delete(%Conn{} = conn, _params) do
    user = conn.assigns.current_user

    with :ok <- authorize(user, :webhook, :delete) do
      Accounts.delete_webhook_token(user)
      send_resp(conn, 204, "")
    end
  end
end
