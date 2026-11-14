defmodule ExNVRWeb.API.DeviceControllerTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures}

  alias ExNVR.Devices

  @moduletag :tmp_dir

  setup %{conn: conn} do
    %{conn: log_in_user_with_access_token(conn, user_fixture())}
  end

  describe "POST /api/devices" do
    test "create a new device", %{conn: conn} do
      total_devices = Devices.list() |> length()

      conn
      |> post(~p"/api/devices", valid_device_attributes())
      |> json_response(201)

      assert length(Devices.list()) == total_devices + 1
    end

    test "create a new device with invalid params", %{conn: conn} do
      response =
        conn
        |> post(~p"/api/devices", valid_device_attributes(%{name: ""}))
        |> json_response(400)

      assert response["code"] == "BAD_ARGUMENT"
    end

    test "create a new device with unauthorized role", %{conn: conn} do
      user_conn = log_in_user_with_access_token(conn, user_fixture(%{role: :user}))

      response =
        user_conn
        |> post(~p"/api/devices", valid_device_attributes())
        |> json_response(403)

      assert response["message"] == "Forbidden"
    end
  end

  describe "PUT/PATCH /api/devices/:id" do
    setup ctx do
      %{device: camera_device_fixture(ctx.tmp_dir)}
    end

    test "update a device", %{conn: conn, device: device} do
      conn
      |> put(~p"/api/devices/#{device.id}", %{
        name: "Updated Name"
      })
      |> json_response(200)

      updated_device = Devices.get!(device.id)
      assert updated_device.name == "Updated Name"
    end

    test "update a device by unauthorized user", %{conn: conn, device: device} do
      user_conn = log_in_user_with_access_token(conn, user_fixture(%{role: :user}))

      response =
        user_conn
        |> put(~p"/api/devices/#{device.id}", %{
          name: "Updated Name"
        })
        |> json_response(403)

      assert response["message"] == "Forbidden"
    end
  end

  describe "GET /api/devices" do
    test "get all devices (empty list)", %{conn: conn} do
      response =
        conn
        |> get("/api/devices/")
        |> json_response(200)

      assert response == []
    end

    test "get all devices (existing devices)", %{conn: conn, tmp_dir: tmp_dir} do
      devices =
        Enum.map(1..10, fn _ ->
          camera_device_fixture(tmp_dir)
        end)

      total_devices = devices |> length()

      response =
        conn
        |> get("/api/devices/")
        |> json_response(200)

      assert length(response) == total_devices
    end
  end

  describe "GET /api/devices/:id" do
    setup ctx do
      %{device: camera_device_fixture(ctx.tmp_dir)}
    end

    test "get device", %{conn: conn, device: device} do
      response =
        conn
        |> get(~p"/api/devices/#{device.id}")
        |> json_response(200)

      assert device.id == response["id"]

      assert device.stream_config.stream_uri == response["stream_config"]["stream_uri"]
      assert device.stream_config.sub_stream_uri == response["stream_config"]["sub_stream_uri"]
      assert device.stream_config.filename == response["stream_config"]["filename"]

      assert device.credentials.username == response["credentials"]["username"]
      assert device.credentials.password == response["credentials"]["password"]
    end

    test "get device with filtered fields", %{conn: conn, device: device} do
      user = user_fixture(%{role: :user})
      user_conn = log_in_user_with_access_token(conn, user)

      response =
        user_conn
        |> get(~p"/api/devices/#{device.id}")
        |> json_response(200)

      refute Map.get(response, "settings")
      refute Map.get(response, "credentials")
      refute Map.get(response, "stream_config")
    end

    test "device not found", %{conn: conn} do
      conn
      |> get(~p"/api/devices/#{UUID.uuid4()}")
      |> response(404)
    end
  end

  describe "DELETE /api/devices/:id" do
    setup ctx do
      %{device: camera_device_fixture(ctx.tmp_dir)}
    end

    test "Delete device", %{conn: conn, device: device} do
      conn
      |> delete(~p"/api/devices/#{device.id}")
      |> response(204)

      refute Devices.get(device.id)
    end

    test "delete a device by unauthorized user", %{conn: conn, device: device} do
      user_conn = log_in_user_with_access_token(conn, user_fixture(%{role: :user}))

      user_conn
      |> delete(~p"/api/devices/#{device.id}")
      |> response(403)
    end
  end
end
