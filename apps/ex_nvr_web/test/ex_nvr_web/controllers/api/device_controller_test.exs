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
        |> post(~p"/api/devices", valid_device_attributes(name: ""))
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
end
