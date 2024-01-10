defmodule ExNVRWeb.Api.EventsControllerTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures, EventsFixture}

  alias ExNVR.Events

  @valid_lpr_event_attributes %{
    "plate" => "01-D-12345",
    "direction" => "forward",
    "type" => "visitor",
    "confidence" => "0.7",
    "vehicle_type" => "Bus",
    "vehicle_color" => "red",
    "plate_color" => "white",
    "coordinate_x1" => "0",
    "coordinate_y1" => "100",
    "coordinate_x2" => "0",
    "coordinate_y2" => "50",
    "time" =>
      ~U"2023-12-12T10:00:00Z"
      |> DateTime.to_iso8601()
      |> String.replace("T", " "),
    "plate_image" =>
      "../../fixtures/license-plate.jpg"
      |> Path.expand(__DIR__)
      |> File.read!()
      |> Base.encode64(),
    "full_image" =>
      "../../fixtures/license-plate.jpg"
      |> Path.expand(__DIR__)
      |> File.read!()
      |> Base.encode64()
  }

  setup %{conn: conn} do
    device = device_fixture(%{vendor: "milesight", settings: %{storage_address: "/tmp"}})

    token_conn = log_in_user_with_access_token(conn, user_fixture())

    user_conn =
      log_in_user_with_username_password(
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
        @valid_lpr_event_attributes
      )
      |> response(201)
    end

    test "create a new random event", %{user_conn: conn, device: device} do
      response =
        conn
        |> post(
          ~p"/api/events?type=random&device_id=#{device.id}",
          @valid_lpr_event_attributes
        )
        |> response(404)
    end

    test "Missing query params", %{user_conn: conn} do
      conn
      |> post(~p"/api/events")
      |> response(404)
    end
  end

  describe "GET /api/events" do
    setup %{device: device} = ctx do
      event = lpr_event_fixture(device)

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
