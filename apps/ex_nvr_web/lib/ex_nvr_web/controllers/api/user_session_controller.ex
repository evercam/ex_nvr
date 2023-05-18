defmodule ExNVRWeb.API.UserSessionController do
  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController

  alias Ecto.Changeset
  alias ExNVR.Accounts
  alias ExNVR.Accounts.User

  def login(conn, params) do
    with {:ok, %{username: username, password: pass}} <- validate_login_params(params),
         %User{} = user <- Accounts.get_user_by_email_and_password(username, pass) do
      token = Accounts.generate_user_access_token(user)
      json(conn, %{access_token: token})
    else
      nil ->
        conn
        |> put_status(400)
        |> json(%{
          code: "INVALID_CREDENTIALS",
          message: "invalid email or password"
        })

      error ->
        error
    end
  end

  defp validate_login_params(params) do
    types = %{
      username: :string,
      password: :string
    }

    {%{}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.validate_required(Map.keys(types))
    |> Changeset.apply_action(:create)
  end
end
