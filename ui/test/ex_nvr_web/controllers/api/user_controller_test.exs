defmodule ExNVRWeb.API.UserControllerTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.AccountsFixtures

  alias ExNVR.Accounts

  setup %{conn: conn} do
    %{conn: log_in_user_with_access_token(conn, user_fixture())}
  end

  describe "GET /api/users" do
    test "get all users using an unauthorized role", %{conn: conn} do
      user_conn = log_in_user_with_access_token(conn, user_fixture(%{role: :user}))

      response =
        user_conn
        |> get(~p"/api/users/")
        |> json_response(403)

      assert response["message"] == "Forbidden"
    end

    test "get all users (empty list except user used in conn)", %{conn: conn} do
      response =
        conn
        |> get("/api/users/")
        |> json_response(200)

      assert length(response) == 1
    end

    test "get all users (existing users)", %{conn: conn} do
      Enum.map(1..10, fn _ ->
        user_fixture(%{role: :user})
      end)

      total_users_nb = Accounts.count_users()
      current_users = Accounts.list()

      response =
        conn
        |> get("/api/users/")
        |> json_response(200)

      assert length(response) == total_users_nb

      assert Enum.map(response, & &1["id"]) |> MapSet.new() ==
               Enum.map(current_users, & &1.id) |> MapSet.new()
    end
  end

  describe "GET /api/users/:id" do
    setup do
      %{user: user_fixture(%{role: :user})}
    end

    test "get user using an unauthorized role", %{conn: conn, user: user} do
      user_conn = log_in_user_with_access_token(conn, user_fixture(%{role: :user}))

      response =
        user_conn
        |> get(~p"/api/users/#{user.id}")
        |> json_response(403)

      assert response["message"] == "Forbidden"
    end

    test "get user", %{conn: conn, user: user} do
      response =
        conn
        |> get(~p"/api/users/#{user.id}")
        |> json_response(200)

      assert user.id == response["id"]
      assert user.first_name == response["first_name"]
      assert user.last_name == response["last_name"]
      assert user.username == response["username"]
      assert user.email == response["email"]
      assert to_string(user.role) == response["role"]
      assert to_string(user.language) == response["language"]
    end

    test "user not found", %{conn: conn} do
      conn
      |> get(~p"/api/users/#{UUID.uuid4()}")
      |> response(404)
    end
  end

  describe "POST /api/users" do
    test "create a new user using an unauthorized role", %{conn: conn} do
      user_conn = log_in_user_with_access_token(conn, user_fixture(%{role: :user}))

      response =
        user_conn
        |> post(~p"/api/users", valid_user_full_attributes())
        |> json_response(403)

      assert response["message"] == "Forbidden"
    end

    test "create a new user", %{conn: conn} do
      total_users = Accounts.count_users()

      conn
      |> post(~p"/api/users", valid_user_full_attributes())
      |> json_response(201)

      assert Accounts.count_users() == total_users + 1
    end

    test "create a new user with invalid params", %{conn: conn} do
      response =
        conn
        |> post(
          ~p"/api/users",
          valid_user_full_attributes(%{first_name: "", email: "email with spaces"})
        )
        |> json_response(400)

      assert response["code"] == "BAD_ARGUMENT"
    end
  end

  describe "PUT/PATCH /api/users/:id" do
    setup do
      %{user: user_fixture(%{role: :user})}
    end

    test "update a user using an unauthorized role", %{conn: conn, user: user} do
      user_conn = log_in_user_with_access_token(conn, user_fixture(%{role: :user}))

      response =
        user_conn
        |> put(~p"/api/users/#{user.id}", %{
          first_name: "Updated Name"
        })
        |> json_response(403)

      assert response["message"] == "Forbidden"
    end

    test "update a user", %{conn: conn, user: user} do
      conn
      |> put(~p"/api/users/#{user.id}", %{
        first_name: "Updated Name",
        role: "admin"
      })
      |> json_response(200)

      updated_user = Accounts.get_user!(user.id)
      assert updated_user.first_name == "Updated Name"
      assert updated_user.role == :admin
    end
  end

  describe "DELETE /api/users/:id" do
    setup do
      %{user: user_fixture(%{role: :user})}
    end

    test "delete a user using an unauthorized role", %{conn: conn, user: user} do
      user_conn = log_in_user_with_access_token(conn, user_fixture(%{role: :user}))

      user_conn
      |> delete(~p"/api/users/#{user.id}")
      |> response(403)
    end

    test "delete user successfully", %{conn: conn, user: user} do
      conn
      |> delete(~p"/api/users/#{user.id}")
      |> response(204)

      refute Accounts.get_user(user.id)
    end
  end
end
