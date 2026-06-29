defmodule ExNVRWeb.API.RemoteStorageTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.AccountsFixtures
  import ExNVR.RemoteStoragesFixtures

  alias ExNVR.RemoteStorages

  setup %{conn: conn} do
    %{conn: log_in_user_with_access_token(conn, user_fixture())}
  end

  describe "GET /api/remote-storages" do
    test "get all remote_storages using an unauthorized role", %{conn: conn} do
      user_conn = log_in_user_with_access_token(conn, user_fixture(%{role: :user}))

      response =
        user_conn
        |> get(~p"/api/remote-storages/")
        |> json_response(403)

      assert response["message"] == "Forbidden"
    end

    test "get all remote_storages (empty list)", %{conn: conn} do
      response =
        conn
        |> get("/api/remote-storages/")
        |> json_response(200)

      assert Enum.empty?(response)
    end

    test "get all remote_storages (remote_storages)", %{conn: conn} do
      Enum.map(1..10, fn _ ->
        remote_storage_fixture()
      end)

      total_remote_storages_nb = RemoteStorages.count_remote_storages()
      current_remote_storages = RemoteStorages.list()

      response =
        conn
        |> get("/api/remote-storages/")
        |> json_response(200)

      assert length(response) == total_remote_storages_nb

      assert Enum.map(response, & &1["id"]) |> MapSet.new() ==
               Enum.map(current_remote_storages, & &1.id) |> MapSet.new()
    end
  end

  describe "GET /api/remote-storages/:id" do
    setup do
      %{remote_storage: remote_storage_fixture()}
    end

    test "get remote_storage", %{conn: conn, remote_storage: remote_storage} do
      response =
        conn
        |> get(~p"/api/remote-storages/#{remote_storage.id}")
        |> json_response(200)

      assert remote_storage.id == response["id"]
      assert remote_storage.name == response["name"]
      assert to_string(remote_storage.type) == response["type"]
      assert remote_storage.url == response["url"]
    end

    test "remote_storage not found", %{conn: conn} do
      conn
      |> get(~p"/api/remote-storages/100000")
      |> response(404)
    end
  end

  describe "POST /api/remote-storages" do
    test "create a new remote_storage using an unauthorized role", %{conn: conn} do
      user_conn = log_in_user_with_access_token(conn, user_fixture(%{role: :user}))

      response =
        user_conn
        |> post(~p"/api/remote-storages", valid_remote_storage_attributes())
        |> json_response(403)

      assert response["message"] == "Forbidden"
    end

    test "create a new remote_storage", %{conn: conn} do
      response =
        conn
        |> post(~p"/api/remote-storages", valid_remote_storage_attributes())
        |> json_response(201)

      [remote_storage] = RemoteStorages.list()

      assert remote_storage.id == response["id"]
      assert remote_storage.name == response["name"]
      assert to_string(remote_storage.type) == response["type"]
      assert remote_storage.url == response["url"]
    end

    test "create a new remote_storage with invalid params", %{conn: conn} do
      response =
        conn
        |> post(
          ~p"/api/remote-storages",
          valid_remote_storage_attributes(%{name: ""})
        )
        |> json_response(400)

      assert response["code"] == "BAD_ARGUMENT"
    end
  end

  describe "PUT/PATCH /api/remote-storages/:id" do
    setup do
      %{remote_storage: remote_storage_fixture()}
    end

    test "update a remote_storage using an unauthorized role", %{
      conn: conn,
      remote_storage: remote_storage
    } do
      user_conn = log_in_user_with_access_token(conn, user_fixture(%{role: :user}))

      response =
        user_conn
        |> put(~p"/api/remote-storages/#{remote_storage.id}", %{
          name: "Updated Name"
        })
        |> json_response(403)

      assert response["message"] == "Forbidden"
    end

    test "update a remote_storage", %{conn: conn, remote_storage: remote_storage} do
      url = "https://example-test-remote-storage#{System.unique_integer()}"

      conn
      |> put(~p"/api/remote-storages/#{remote_storage.id}", %{
        type: :http,
        url: url
      })
      |> json_response(200)

      updated_remote_storage = RemoteStorages.get!(remote_storage.id)
      assert updated_remote_storage.name == remote_storage.name
      assert updated_remote_storage.type == remote_storage.type
      assert updated_remote_storage.url == url
      assert updated_remote_storage.id == remote_storage.id
    end
  end

  describe "DELETE /api/remote-storages/:id" do
    setup do
      %{remote_storage: remote_storage_fixture()}
    end

    test "delete a remote_storage using an unauthorized role", %{
      conn: conn,
      remote_storage: remote_storage
    } do
      user_conn = log_in_user_with_access_token(conn, user_fixture(%{role: :user}))

      user_conn
      |> delete(~p"/api/remote-storages/#{remote_storage.id}")
      |> response(403)
    end

    test "delete remote_storage successfully", %{conn: conn, remote_storage: remote_storage} do
      conn
      |> delete(~p"/api/remote-storages/#{remote_storage.id}")
      |> response(204)

      refute RemoteStorages.get(remote_storage.id)
    end
  end
end
