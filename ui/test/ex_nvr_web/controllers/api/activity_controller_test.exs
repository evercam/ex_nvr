defmodule ExNVRWeb.API.ActivityControllerTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, ActivityFixtures}

  @moduletag :tmp_dir

  setup %{conn: conn, tmp_dir: tmp_dir} do
    conn = log_in_user_with_access_token(conn, user_fixture())
    device = camera_device_fixture(tmp_dir)
    now = DateTime.utc_now()

    auth_entry =
      entry_fixture(time: DateTime.add(now, -1, :minute), category: :auth, action: "auth.login")

    device_entry = entry_fixture(time: now, device: device)

    %{
      conn: conn,
      device: device,
      entries: [auth_entry, device_entry]
    }
  end

  describe "GET /api/activity" do
    test "is available to non admin users", %{conn: conn} do
      response =
        conn
        |> log_in_user_with_access_token(user_fixture(%{role: :user}))
        |> get(~p"/api/activity")
        |> json_response(200)

      assert length(response["data"]) == 2
    end

    test "lists all entries, newest first", %{conn: conn, entries: [auth_entry, device_entry]} do
      response = conn |> get(~p"/api/activity") |> json_response(200)

      assert response["meta"] == %{
               "current_page" => 1,
               "page_size" => 50,
               "total_count" => 2,
               "total_pages" => 1
             }

      assert Enum.map(response["data"], & &1["id"]) == [device_entry.id, auth_entry.id]
      assert [%{"category" => "device", "action" => "device.updated"} | _] = response["data"]
    end

    test "filters entries", %{conn: conn, entries: [auth_entry, _device_entry]} do
      params = %{filters: %{"0" => %{field: "category", op: "==", value: "auth"}}}

      response = conn |> get(~p"/api/activity?#{params}") |> json_response(200)

      assert [%{"id" => id}] = response["data"]
      assert id == auth_entry.id
    end

    test "returns bad argument on invalid filters", %{conn: conn} do
      params = %{filters: %{"0" => %{field: "category", op: "==", value: "unknown"}}}

      response = conn |> get(~p"/api/activity?#{params}") |> json_response(400)

      assert response["code"] == "BAD_ARGUMENT"
    end
  end

  describe "GET /api/devices/:device_id/activity" do
    test "lists the device entries", %{conn: conn, device: device, entries: [_auth, device_entry]} do
      response = conn |> get(~p"/api/devices/#{device.id}/activity") |> json_response(200)

      assert [%{"id" => id, "device_name" => name}] = response["data"]
      assert id == device_entry.id
      assert name == device.name
    end

    test "is available to non admin users", %{conn: conn, device: device} do
      conn
      |> log_in_user_with_access_token(user_fixture(%{role: :user}))
      |> get(~p"/api/devices/#{device.id}/activity")
      |> json_response(200)
    end
  end
end
