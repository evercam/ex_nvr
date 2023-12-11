defmodule ExNVRWeb.API.DeviceControllerTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures}

  alias ExNVR.Devices

  @moduletag :tmp_dir


  defp format_device_info_per_role(user, device) do
    case user.role do
      :user ->
        %{
          "id" => device.id,
          "name" => device.name,
          "type" => Atom.to_string(device.type),
          "state" => Atom.to_string(device.state),
          "timezone" => device.timezone
        }

      :admin ->
        %{
          "id" => device.id,
          "name" => device.name,
          "type" => Atom.to_string(device.type),
          "state" => Atom.to_string(device.state),
          "timezone" => device.timezone,
          "inserted_at" => DateTime.to_iso8601(device.inserted_at),
          "updated_at" => DateTime.to_iso8601(device.updated_at),
          "stream_config" => %{
            "stream_uri" => device.stream_config.stream_uri,
            "sub_stream_uri" => device.stream_config.sub_stream_uri,
            "filename" => device.stream_config.filename,
            "duration" => device.stream_config.duration,
            "temporary_path" => device.stream_config.temporary_path
          },
          "credentials" => %{
            "username" => device.credentials.username,
            "password" => device.credentials.password
          },
          "settings" => %{
            "generate_bif" => device.settings.generate_bif,
            "storage_address" => device.settings.storage_address
          }
        }
    end
  end

  setup %{conn: conn} do
    admin = user_fixture()
    %{conn: log_in_user_with_access_token(conn, admin), admin: admin}
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

    test "create a new device with Unauthorized role", %{conn: conn} do
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
      %{device: device_fixture(%{settings: %{storage_address: ctx.tmp_dir}})}
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

    test "get all devices (existing devices - admin)", %{conn: conn, tmp_dir: tmp_dir, admin: admin} do
      devices =
        Enum.map(1..10, fn _ ->
          device_fixture(%{settings: %{storage_address: tmp_dir}})
        end)

      total_devices = devices |> length()

      response =
        conn
        |> get("/api/devices/")
        |> json_response(200)

      assert length(response) == total_devices
      assert Enum.map(devices, &format_device_info_per_role(admin, &1)) == response
    end

    test "get all devices (existing devices - :user)", %{conn: conn, tmp_dir: tmp_dir} do
      user = user_fixture(%{role: :user})
      user_conn = log_in_user_with_access_token(conn, user)

      devices =
        Enum.map(1..10, fn _ ->
          device_fixture(%{settings: %{storage_address: tmp_dir}})
        end)

      total_devices = devices |> length()

      response =
        user_conn
        |> get("/api/devices/")
        |> json_response(200)

      assert length(response) == total_devices
      assert Enum.map(devices, &format_device_info_per_role(user, &1)) == response
    end
  end

  describe "GET /api/devices/:id" do
    setup ctx do
      %{device: device_fixture(%{settings: %{storage_address: ctx.tmp_dir}})}
    end

    test "get device (:admin)", %{conn: conn, device: device, admin: admin} do
      response =
        conn
        |> get(~p"/api/devices/#{device.id}")
        |> json_response(200)

      assert format_device_info_per_role(admin, device) == response
    end

    test "get device (:user)", %{conn: conn, device: device} do
      user = user_fixture(%{role: :user})
      user_conn = log_in_user_with_access_token(conn, user)
      response =
        user_conn
        |> get(~p"/api/devices/#{device.id}")
        |> json_response(200)

      assert format_device_info_per_role(user, device) == response
    end

    test "device not found", %{conn: conn} do
      conn
      |> get(~p"/api/devices/#{UUID.uuid4()}")
      |> response(404)
    end
  end
end
