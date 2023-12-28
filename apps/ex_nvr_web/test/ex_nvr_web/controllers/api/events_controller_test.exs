defmodule ExNVRWeb.Api.EventsControllerTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures}

  alias ExNVR.Events

  @lpr_event_parameter %{
    "plate" => "sfdsfd",
    "direction" => "forward",
    "plate_image" => ""
  }

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
          @lpr_event_parameter
        )
        |> json_response(201)

      assert event["plate_number"] == @lpr_event_parameter["plate"]
      assert event["direction"] == @lpr_event_parameter["direction"]
    end

    test "create a new random event", %{conn: conn, device: device} do
      conn
      |> post(
        ~p"/api/events?type=random&device_id=#{device.id}",
        %{
          "plate" => "sfdsfd",
          "direction" => "forward",
          "plate_image" => ""
        }
      )
      |> response(422)
    end
  end
end
