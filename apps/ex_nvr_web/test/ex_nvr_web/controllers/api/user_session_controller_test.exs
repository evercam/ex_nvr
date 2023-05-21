defmodule ExNVRWeb.API.UserSessionControllerTest do
  use ExNVRWeb.ConnCase

  import ExNVR.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "POST /api/users/login" do
    test "logs the user in", %{conn: conn, user: user} do
      response =
        post(conn, ~p"/api/users/login", %{
          username: user.email,
          password: valid_user_password()
        })
        |> json_response(200)

      assert response["access_token"]
    end

    test "missing required field", %{conn: conn, user: user} do
      response =
        post(conn, ~p"/api/users/login", %{username: user.email})
        |> json_response(400)

      assert response["code"] == "BAD_ARGUMENT"
    end

    test "invalid credentials", %{conn: conn, user: user} do
      response =
        post(conn, ~p"/api/users/login", %{username: user.email, password: "random pass"})
        |> json_response(400)

      assert response["code"] == "INVALID_CREDENTIALS"
    end
  end
end
