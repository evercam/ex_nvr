defmodule ExNVRWeb.Api.EventControllerTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures, EventsFixtures}

  @moduletag :tmp_dir

  @plate_image "test/fixtures/license-plate.jpg"

  @milesight_lpr_event %{
    "plate" => "01-D-12345",
    "time" => "2024-02-01 06:00:05.509",
    "direction" => "Approach",
    "type" => "White",
    "resolution_width" => "1920",
    "resolution_height" => "1080",
    "coordinate_x1" => "0",
    "coordinate_y1" => "100",
    "coordinate_x2" => "0",
    "coordinate_y2" => "50",
    "plate_image" => @plate_image |> File.read!() |> Base.encode64()
  }

  setup %{tmp_dir: tmp_dir} do
    device = camera_device_fixture(tmp_dir, %{vendor: "Milesight Technology Co.,Ltd."})
    [device: device]
  end

  describe "POST /api/device/:device/events" do
    setup do
      %{token: ExNVR.Accounts.generate_webhook_token(user_fixture())}
    end

    test "create a new lpr event", %{conn: conn, device: device, token: token} do
      conn
      |> post(
        ~p"/api/devices/#{device.id}/events?event_type=lpr&token=#{token}",
        @milesight_lpr_event
      )
      |> response(201)

      assert {:ok, [_plate]} = File.ls(ExNVR.Model.Device.lpr_thumbnails_dir(device))
    end

    test "return not found on wrong event type", %{conn: conn, device: device, token: token} do
      conn
      |> post(
        ~p"/api/devices/#{device.id}/events?event_type=alpr&token=#{token}",
        @milesight_lpr_event
      )
      |> json_response(404)
    end

    test "return unauthorized on wrong/missing token", %{conn: conn, device: device} do
      conn
      |> post(~p"/api/devices/#{device.id}/events?event_type=alpr", @milesight_lpr_event)
      |> json_response(401)
    end

    test "return not found for not implemented camera vendor", %{
      conn: conn,
      tmp_dir: tmp_dir,
      token: token
    } do
      device = camera_device_fixture(tmp_dir)

      conn
      |> post(
        ~p"/api/devices/#{device.id}/events?event_type=alpr&token=#{token}",
        @milesight_lpr_event
      )
      |> json_response(404)
    end
  end

  describe "GET /api/events/lpr" do
    setup %{conn: conn} do
      %{conn: log_in_user_with_access_token(conn, user_fixture())}
    end

    test "get events", %{conn: conn} do
      event_fixture(:lpr, camera_device_fixture())
      event_fixture(:lpr, camera_device_fixture())

      response =
        conn
        |> get(~p"/api/events/lpr")
        |> json_response(200)

      assert response["meta"]["total_count"] == 2
      assert [%{"plate_image" => nil}, %{"plate_image" => nil}] = response["data"]
    end

    test "filter events", %{conn: conn} do
      device = camera_device_fixture()
      event_1 = event_fixture(:lpr, device)
      event_fixture(:lpr, camera_device_fixture())

      response =
        conn
        |> get(~p"/api/events/lpr?filters[0][field]=device_id&filters[0][value]=#{device.id}")
        |> json_response(200)

      assert response["meta"]["total_count"] == 1
      assert List.first(response["data"])["id"] == event_1.id
    end

    test "get events with plate image", %{conn: conn} do
      event_fixture(:lpr, camera_device_fixture())
      event_fixture(:lpr, camera_device_fixture())

      response =
        conn
        |> get(~p"/api/events/lpr?include_plate_image=true")
        |> json_response(200)

      assert response["meta"]["total_count"] == 2
      assert [%{"plate_image" => image}, %{"plate_image" => image}] = response["data"]
      assert not is_nil(image)
    end

    test "invalid params", %{conn: conn} do
      response =
        conn
        |> get("/api/events/lpr?filters[0][field]=device&order_by=some_field")
        |> json_response(400)

      assert response["code"] == "BAD_ARGUMENT"
    end
  end
end
