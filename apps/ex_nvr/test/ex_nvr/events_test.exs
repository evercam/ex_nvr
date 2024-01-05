defmodule ExNVR.EventsTest do
  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import ExNVR.RecordingsFixtures

  alias ExNVR.{Events}
  alias ExNVR.Model.LPREvent

  @moduletag :tmp_dir
  @lpr_plate "01-D-12345"
  @lpr_direction "forward"
  @lpr_time ~U"2023-12-12T10:00:00Z"
  @lpr_list_type "visitor"
  @lpr_confidence 0.7
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

  setup ctx do
    device = device_fixture(%{settings: %{storage_address: ctx.tmp_dir}})
    %{device: device}
  end

  describe "Create" do
    test "Create lpr events", %{device: device} do
      assert {:ok, event} =
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

      assert event
             |> Events.lpr_event_filename()
             |> File.exists?()

      assert event
             |> Events.lpr_event_filename("full_picture")
             |> File.exists?()

      assert event.plate_number == @lpr_plate
      assert event.direction == @lpr_direction
      assert event.list_type == @lpr_list_type
      assert event.confidence == @lpr_confidence
      assert event.vehicle_type == @lpr_vehicle_type
      assert event.vehicle_color == @lpr_vehicle_color
      assert event.plate_color == @lpr_plate_color
      assert event.bounding_box == %LPREvent.BoundingBox{
        x1: String.to_integer(@lpr_coordinates_x1),
        y1: String.to_integer(@lpr_coordinates_y1),
        x2: String.to_integer(@lpr_coordinates_x2),
        y2: String.to_integer(@lpr_coordinates_y2),
      }

      assert DateTime.compare(@lpr_time, event.capture_time) == :eq
    end
  end

  describe "Get" do
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

    test "Get lpr events", %{device: device} do
      assert length(Events.list(device.id, :lpr)) > 0
    end
  end
end
