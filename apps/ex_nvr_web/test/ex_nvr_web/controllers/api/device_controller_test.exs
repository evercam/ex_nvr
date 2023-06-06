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
end
