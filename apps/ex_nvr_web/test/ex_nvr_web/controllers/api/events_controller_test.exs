defmodule ExNVRWeb.Api.EventsControllerTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures}

  alias ExNVR.Events

  @lpr_plate "01-D-12345"
  @lpr_direction "forward"
  @lpr_time ~U"2023-12-12T10:00:00Z"
  @lpr_plate_image "../fixtures/images/license-plate.jpg"
                   |> Path.expand(__DIR__)
                   |> Base.encode64()

  setup do
    device = device_fixture(%{settings: %{storage_address: "/tmp"}})

    %{device: device}
  end

  describe "POST /api/events" do
    test "create a new lpr event", %{conn: conn, device: device} do
      assert %{"event" => event} =
               conn
               |> post(
                 ~p"/api/events?type=lpr&device_id=#{device.id}",
                 %{
                   "plate" => @lpr_plate,
                   "direction" => @lpr_direction,
                   "plate_image" => @lpr_plate_image,
                   "time" =>
                     @lpr_time
                     |> DateTime.to_iso8601()
                     |> String.replace("T", " ")
                 }
               )
               |> json_response(201)

      assert event["plate_number"] == @lpr_plate
      assert event["direction"] == @lpr_direction
      assert event["plate_image"] == @lpr_plate_image
      assert {:ok, date_time, 0} = DateTime.from_iso8601(event["capture_time"])
      assert DateTime.compare(@lpr_time, date_time) == :eq
    end

    test "create a new random event", %{conn: conn, device: device} do
      response =
        conn
        |> post(
          ~p"/api/events?type=random&device_id=#{device.id}",
          %{
            "plate" => @lpr_plate,
            "direction" => @lpr_direction,
            "plate_image" => @lpr_plate_image,
            "time" =>
              @lpr_time
              |> DateTime.to_iso8601()
              |> String.replace("T", " ")
          }
        )
        |> response(500)
    end

    test "Missing query params", %{conn: conn} do
      conn
      |> post(~p"/api/events")
      |> response(422)
    end
  end

  describe "GET /api/events" do
    setup %{device: device} = ctx do
      {:ok, event} =
        Events.create(
          %{
            "plate" => @lpr_plate,
            "direction" => @lpr_direction,
            "plate_image" => @lpr_plate_image,
            "time" =>
              @lpr_time
              |> DateTime.to_iso8601()
              |> String.replace("T", " ")
          },
          device,
          "lpr"
        )

      Map.put(ctx, :event, event)
    end

    test "get events", %{conn: conn, device: device} do
      conn
      |> get(~p"/api/events?device_id=#{device.id}&type=lpr")
      |> json_response(200)
    end
  end
end
