defmodule ExNVRWeb.Api.EventControllerTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures, EventsFixtures}

  alias ExNVR.Model.Device

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

  @generic_event %{
    "location" => "kitchen",
    "motion_level" => 9000
  }

  @generic_event_unsupported_media_type "location: kitchen"

  setup %{tmp_dir: tmp_dir} do
    device =
      camera_device_fixture(tmp_dir, %{
        vendor: "Milesight Technology Co.,Ltd.",
        timezone: "Africa/Algiers"
      })

    [device: device]
  end

  describe "POST /api/device/:device/events" do
    setup do
      %{token: ExNVR.Accounts.generate_webhook_token(user_fixture())}
    end

    test "create a new lpr event", %{conn: conn, device: device, token: token} do
      conn
      |> post(
        ~p"/api/devices/#{device.id}/events/lpr?token=#{token}",
        @milesight_lpr_event
      )
      |> response(201)

      assert {:ok, [_plate]} = File.ls(Device.lpr_thumbnails_dir(device))
    end

    test "create a new generic event", %{conn: conn, device: device, token: token} do
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/api/devices/#{device.id}/events?type=my_type&token=#{token}",
        @generic_event
      )
      |> response(201)

      {:ok, {[event], _}} = ExNVR.Events.list_events(%{})

      assert event.device_id == device.id
      assert event.metadata == @generic_event
      assert event.type == "my_type"
    end

    test "return unsupported content type when content is not json", %{
      conn: conn,
      device: device,
      token: token
    } do
      conn
      |> put_req_header("content-type", "text/plain")
      |> post(
        ~p"/api/devices/#{device.id}/events?type=my_type&token=#{token}",
        @generic_event_unsupported_media_type
      )
      |> response(415)
    end

    test "return bad_argument when type is missing", %{
      conn: conn,
      device: device,
      token: token
    } do
      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/devices/#{device.id}/events?token=#{token}",
          %{}
        )
        |> json_response(400)

      assert response["code"] == "BAD_ARGUMENT"
    end

    test "return unauthorized on wrong/missing token", %{conn: conn, device: device} do
      conn
      |> post(~p"/api/devices/#{device.id}/events/lpr", @milesight_lpr_event)
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
        ~p"/api/devices/#{device.id}/events/lpr?token=#{token}",
        @milesight_lpr_event
      )
      |> json_response(404)
    end

    test "create generic event with naive timestamp format", %{
      conn: conn,
      device: device,
      token: token
    } do
      utc_time = ~U[2025-04-01 09:00:00.000000Z]
      dz_naive_time = "2025-04-01 10:00:00"
      payload = %{"time" => dz_naive_time}

      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/api/devices/#{device.id}/events?type=my_type&token=#{token}",
        payload
      )
      |> response(201)

      {:ok, {[event], _}} = ExNVR.Events.list_events(%{})

      assert event.time == utc_time
      assert event.metadata["time"] == dz_naive_time
    end

    test "create generic event with ISO timestamp format", %{
      conn: conn,
      device: device,
      token: token
    } do
      utc_time = ~U[2025-04-01 09:00:00.000000Z]
      dz_time = "2025-04-01T10:00:00+01:00"
      payload = %{"time" => dz_time}

      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/api/devices/#{device.id}/events?type=my_type&token=#{token}",
        payload
      )
      |> response(201)

      {:ok, {[event], _}} = ExNVR.Events.list_events(%{})

      assert event.time == utc_time
      assert event.metadata["time"] == dz_time
    end

    test "creating a generic event with no timestamp, defaults to now", %{
      conn: conn,
      device: device,
      token: token
    } do
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/api/devices/#{device.id}/events?type=my_type&token=#{token}",
        @generic_event
      )
      |> response(201)

      {:ok, {[event], _}} = ExNVR.Events.list_events(%{})

      assert DateTime.diff(event.time, event.inserted_at) == 0
    end
  end

  describe "GET /api/events/lpr" do
    setup %{conn: conn} do
      %{conn: log_in_user_with_access_token(conn, user_fixture())}
    end

    test "get LPR events", %{conn: conn} do
      event_fixture(:lpr, camera_device_fixture())
      event_fixture(:lpr, camera_device_fixture())

      response =
        conn
        |> get(~p"/api/events/lpr")
        |> json_response(200)

      assert response["meta"]["total_count"] == 2
      assert [%{"plate_image" => nil}, %{"plate_image" => nil}] = response["data"]
    end

    test "filter LPR events", %{conn: conn} do
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

    test "get LPR events with plate image", %{conn: conn} do
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

    test "invalid LPR params", %{conn: conn} do
      response =
        conn
        |> get("/api/events/lpr?filters[0][field]=device&order_by=some_field")
        |> json_response(400)

      assert response["code"] == "BAD_ARGUMENT"
    end
  end

  describe "GET /api/events" do
    setup %{conn: conn} do
      %{conn: log_in_user_with_access_token(conn, user_fixture())}
    end

    test "get all events", %{conn: conn, device: device} do
      {:ok, event_1} = event_fixture("motion", device, %{"location" => "kitchen"})
      {:ok, event_2} = event_fixture("fire", device, %{"location" => "barn"})

      response =
        conn
        |> get(~p"/api/events")
        |> json_response(200)

      %{
        "data" => [
          api_event_2,
          api_event_1
        ],
        "meta" => meta
      } = response

      assert meta["total_count"] == 2
      assert api_event_1 |> matches(event_1)
      assert api_event_2 |> matches(event_2)
    end

    test "filter by device_id", %{conn: conn, device: device} do
      {:ok, event_1} = event_fixture("noise", device, %{"decibels" => 93})
      {:ok, _event_2} = event_fixture("vibration", camera_device_fixture(), %{"intensity" => 9})

      response =
        conn
        |> get(~p"/api/events?filters[0][field]=device_id&filters[0][value]=#{device.id}")
        |> json_response(200)

      assert response["meta"]["total_count"] == 1
      assert [api_event] = response["data"]
      assert api_event |> matches(event_1)
    end

    test "filter by time", %{conn: conn, device: device} do
      {:ok, event_1} =
        event_fixture("crowd", device, %{"time" => "2024-01-02T10:00:00Z", "count" => 15})

      {:ok, _event_2} =
        event_fixture("tamper", device, %{"time" => "2024-01-03T10:00:00Z"})

      response =
        conn
        |> get(~p"/api/events?start_date=2024-01-02T00:00:00Z&end_date=2024-01-02T23:59:59Z")
        |> json_response(200)

      assert response["meta"]["total_count"] == 1
      assert [api_event] = response["data"]
      assert api_event |> matches(event_1)
    end

    test "filter by type", %{conn: conn, device: device} do
      {:ok, event_1} = event_fixture("air_quality_alert", device, %{"value" => 130})
      {:ok, _event_2} = event_fixture("ppe_violation", device, %{"item" => "gloves"})

      response =
        conn
        |> get(~p"/api/events?filters[0][field]=type&filters[0][value]=air_quality_alert")
        |> json_response(200)

      assert response["meta"]["total_count"] == 1
      assert [api_event] = response["data"]
      assert api_event |> matches(event_1)
    end

    test "invalid query params return BAD_ARGUMENT", %{conn: conn} do
      response =
        conn
        |> get(~p"/api/events?filters[0][field]=unknown_field")
        |> json_response(400)

      assert response["code"] == "BAD_ARGUMENT"
    end
  end

  defp matches(api_event, %ExNVR.Events.Event{} = event) do
    assert api_event["id"] == event.id
    assert api_event["device_id"] == event.device_id
    assert api_event["type"] == event.type
    assert api_event["metadata"] == event.metadata

    case event.time do
      nil ->
        assert api_event["time"]

      time ->
        {:ok, api_date_time, _} = DateTime.from_iso8601(api_event["time"])
        assert api_date_time == time
    end
  end
end
