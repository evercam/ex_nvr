defmodule ExNVRWeb.Api.EventsControllerTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures}

  alias ExNVR.Events

  setup do
    device = device_fixture(%{settings: %{storage_address: "/tmp"}})

    %{device: device}
  end

  describe "POST /api/events/:device_id" do
    test "create a new lpr event", %{conn: conn, device: device} do
      conn
      |> post(
          ~p"/api/events/#{device.id}?type=lpr",
          %{
            "plate" => "sfdsfd",
            "direction" => "forward",
            "plate_image" => ""
          }
         )
      |> json_response(201)
    end
  end
end
