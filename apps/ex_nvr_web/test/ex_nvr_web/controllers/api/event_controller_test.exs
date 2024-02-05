defmodule ExNVRWeb.Api.EventControllerTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.DevicesFixtures

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
    device =
      device_fixture(%{
        vendor: "Milesight Technology Co.,Ltd.",
        settings: %{storage_address: tmp_dir}
      })

    [device: device]
  end

  describe "POST /api/device/:device/events" do
    test "create a new lpr event", %{conn: conn, device: device} do
      conn
      |> post(~p"/api/devices/#{device.id}/events?event_type=lpr", @milesight_lpr_event)
      |> response(201)

      assert {:ok, [_plate]} = File.ls(ExNVR.Model.Device.lpr_thumbnails_dir(device))
    end

    test "return not found on wrong event type", %{conn: conn, device: device} do
      conn
      |> post(~p"/api/devices/#{device.id}/events?event_type=alpr", @milesight_lpr_event)
      |> json_response(404)
    end

    test "return not found for not implemented camera vendor", %{conn: conn, tmp_dir: tmp_dir} do
      device = device_fixture(%{settings: %{storage_address: tmp_dir}})

      conn
      |> post(~p"/api/devices/#{device.id}/events?event_type=alpr", @milesight_lpr_event)
      |> json_response(404)
    end
  end

  # describe "GET /api/events" do
  #   setup %{device: device} = ctx do
  #     event = lpr_event_fixture(device)

  #     Map.put(ctx, :event, event)
  #   end

  #   test "get events", %{token_conn: conn, device: device} do
  #     response =
  #       conn
  #       |> get(~p"/api/events?filters[0][field]=device_id&filters[0][value]=#{device.id}")
  #       |> json_response(200)

  #     assert length(response["data"]) == 1
  #     assert response["data"] |> Enum.at(0) |> Map.get("device_id") == device.id
  #   end

  #   test "invalid params", %{token_conn: conn} do
  #     response =
  #       conn
  #       |> get("/api/events?filters[0][field]=device&order_by=some_field")
  #       |> json_response(400)

  #     assert response["code"] == "BAD_ARGUMENT"
  #   end
  # end
end
