defmodule ExNVRWeb.Api.EventsControllerTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures}

  alias ExNVR.Events

  @lpr_plate "01-D-12345"
  @lpr_direction "forward"
  @lpr_time ~U"2023-12-12T10:00:00Z"
  @lpr_list_type "visitor"
  @lpr_confidence "0.7"
  @lpr_vehicle_type "Bus"
  @lpr_vehicle_color "red"
  @lpr_plate_color "white"
  @lpr_coordinates_x1 "0"
  @lpr_coordinates_y1 "100"
  @lpr_coordinates_x2 "0"
  @lpr_coordinates_y2 "50"
  @lpr_plate_image "../fixtures/images/license-plate.jpg"
                   |> Path.expand(__DIR__)
                   |> Base.encode64()
  @lpr_full_image "../fixtures/images/license-plate.jpg"
                  |> Path.expand(__DIR__)
                  |> Base.encode64()

  setup %{conn: conn} do
    device = device_fixture(%{vendor: "milesight", settings: %{storage_address: "/tmp"}})

    token_conn = log_in_user_with_access_token(conn, user_fixture())
    user_conn = log_in_user_with_username_password(
      conn,
      user_fixture(%{password: "Password1"}),
      "Password1"
    )


    %{device: device, user_conn: user_conn, token_conn: token_conn}
  end

  describe "POST /api/events" do
    test "create a new lpr event", %{user_conn: conn, device: device} do
      conn
      |> post(
        ~p"/api/events?type=lpr&device_id=#{device.id}",
        %{
          "plate" => @lpr_plate,
          "direction" => @lpr_direction,
          "type" => @lpr_list_type,
          "confidence" => @lpr_confidence,
          "vehicle_type" => @lpr_vehicle_type,
          "vehicle_color" => @lpr_vehicle_color,
          "plate_color" => @lpr_plate_color,
          "coordinate_x1" => @lpr_coordinates_x1,
          "coordinate_y1" => @lpr_coordinates_y1,
          "coordinate_x2" => @lpr_coordinates_x2,
          "coordinate_y2" => @lpr_coordinates_y2,
          "time" =>
            @lpr_time
            |> DateTime.to_iso8601()
            |> String.replace("T", " "),
          "plate_image" => @lpr_plate_image,
          "full_image" => @lpr_full_image
        }
      )
      |> response(201)
    end

    test "create a new random event", %{user_conn: conn, device: device} do
      response =
        conn
        |> post(
          ~p"/api/events?type=random&device_id=#{device.id}",
          %{
            "plate" => @lpr_plate,
            "direction" => @lpr_direction,
            "type" => @lpr_list_type,
            "confidence" => @lpr_confidence,
            "vehicle_type" => @lpr_vehicle_type,
            "vehicle_color" => @lpr_vehicle_color,
            "plate_color" => @lpr_plate_color,
            "coordinate_x1" => @lpr_coordinates_x1,
            "coordinate_y1" => @lpr_coordinates_y1,
            "coordinate_x2" => @lpr_coordinates_x2,
            "coordinate_y2" => @lpr_coordinates_y2,
            "time" =>
              @lpr_time
              |> DateTime.to_iso8601()
              |> String.replace("T", " "),
            "plate_image" => @lpr_plate_image,
            "full_image" => @lpr_full_image
          }
        )
        |> response(500)
    end

    test "Missing query params", %{user_conn: conn} do
      conn
      |> post(~p"/api/events")
      |> response(500)
    end
  end

  describe "GET /api/events" do
    setup %{device: device} = ctx do
      {:ok, event} =
        Events.create_lpr_event(
          %{
          plate_number: @lpr_plate,
          direction: @lpr_direction,
          list_type: @lpr_list_type,
          confidence: @lpr_confidence,
          vehicle_type: @lpr_vehicle_type,
          vehicle_color: @lpr_vehicle_color,
          plate_color: @lpr_plate_color,
          bounding_box: %{
            x1: @lpr_coordinates_x1,
            y1: @lpr_coordinates_y1,
            x2: @lpr_coordinates_x2,
            y2: @lpr_coordinates_y2,
          },
          capture_time:
            @lpr_time
            |> DateTime.to_iso8601()
            |> String.replace("T", " "),
          device_id: device.id,
          type: "lpr"
          },
          @lpr_plate_image,
          @lpr_full_image
        )

      Map.put(ctx, :event, event)
    end

    test "get events", %{token_conn: conn, device: device} do
      response =
        conn
        |> get(~p"/api/events?filters[0][field]=device_id&filters[0][value]=#{device.id}")
        |> json_response(200)

      assert length(response["data"]) == 1
      assert response["data"] |> Enum.at(0) |> Map.get("device_id") == device.id
    end

    test "invalid params", %{token_conn: conn} do
      response =
        conn
        |> get("/api/events?filters[0][field]=device&order_by=some_field")
        |> json_response(400)

      assert response["code"] == "BAD_ARGUMENT"
    end
  end
end
