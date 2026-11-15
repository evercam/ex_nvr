defmodule ExNVRWeb.API.WebhookTokenControllerTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.AccountsFixtures

  alias ExNVR.Accounts

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user_with_access_token(conn, user), user: user}
  end

  describe "GET /api/webhook-token" do
    test "returns 404 when the user has no token", %{conn: conn} do
      conn
      |> get(~p"/api/webhook-token")
      |> json_response(404)
    end

    test "returns the current user's token", %{conn: conn, user: user} do
      token = Accounts.generate_webhook_token(user)

      response =
        conn
        |> get(~p"/api/webhook-token")
        |> json_response(200)

      assert response["token"] == token
      assert {:ok, _datetime, 0} = DateTime.from_iso8601(response["inserted_at"])
    end

    test "does not return another user's token", %{conn: conn} do
      Accounts.generate_webhook_token(user_fixture())

      conn
      |> get(~p"/api/webhook-token")
      |> json_response(404)
    end

    test "is readable by a non-admin user", %{conn: conn} do
      user = user_fixture(%{role: :user})
      token = Accounts.generate_webhook_token(user)

      response =
        conn
        |> log_in_user_with_access_token(user)
        |> get(~p"/api/webhook-token")
        |> json_response(200)

      assert response["token"] == token
    end
  end

  describe "POST /api/webhook-token" do
    test "creates and returns a usable token", %{conn: conn, user: user} do
      response =
        conn
        |> post(~p"/api/webhook-token")
        |> json_response(201)

      assert response["token"] == Accounts.get_webhook_token(user).token
      assert Accounts.verify_webhook_token(Base.url_decode64!(response["token"]))
    end

    test "returns the existing token instead of creating a second one", %{conn: conn, user: user} do
      token = Accounts.generate_webhook_token(user)

      response =
        conn
        |> post(~p"/api/webhook-token")
        |> json_response(200)

      assert response["token"] == token
    end

    test "is forbidden for a non-admin user", %{conn: conn} do
      user = user_fixture(%{role: :user})

      conn
      |> log_in_user_with_access_token(user)
      |> post(~p"/api/webhook-token")
      |> json_response(403)

      refute Accounts.get_webhook_token(user)
    end
  end

  describe "DELETE /api/webhook-token" do
    test "deletes the token", %{conn: conn, user: user} do
      Accounts.generate_webhook_token(user)

      conn
      |> delete(~p"/api/webhook-token")
      |> response(204)

      refute Accounts.get_webhook_token(user)
    end

    test "succeeds when there is no token", %{conn: conn} do
      conn
      |> delete(~p"/api/webhook-token")
      |> response(204)
    end

    test "is forbidden for a non-admin user", %{conn: conn} do
      user = user_fixture(%{role: :user})
      Accounts.generate_webhook_token(user)

      conn
      |> log_in_user_with_access_token(user)
      |> delete(~p"/api/webhook-token")
      |> json_response(403)

      assert Accounts.get_webhook_token(user)
    end
  end

  test "requires authentication" do
    build_conn()
    |> get(~p"/api/webhook-token")
    |> json_response(401)
  end
end
