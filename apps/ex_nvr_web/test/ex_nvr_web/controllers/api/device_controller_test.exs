defmodule ExNVRWeb.API.DeviceControllerTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures}

  alias ExNVR.Devices

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
  end

  describe "PUT/PATCH /api/devices/:id" do
    setup do
      %{device: device_fixture()}
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
  end

  describe "GET /api/devices" do
    test "get all devices (empty list)", %{conn: conn} do
      response =
        conn
        |> get("/api/devices/")
        |> json_response(200)

      assert response == []
    end

    test "get all devices (existing devices)", %{conn: conn} do
      devices =
        Enum.map(1..10, fn _ ->
          device_fixture()
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
    setup do
      %{device: device_fixture()}
    end

    test "get device by :id", %{conn: conn, device: device} do
      response =
        conn
        |> get(~p"/api/devices/#{device.id}")
        |> json_response(200)

      assert device.id == response["id"]
    end

    test "get device by :id (not found)", %{conn: conn} do
      conn
      |> get(~p"/api/devices/#{UUID.uuid4()}")
      |> response(404)
    end
  end
end
