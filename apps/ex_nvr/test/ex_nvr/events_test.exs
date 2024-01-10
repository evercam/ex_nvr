defmodule ExNVR.EventsTest do
  use ExNVR.DataCase

  import ExNVR.{DevicesFixtures, RecordingsFixtures, EventsFixture}

  alias ExNVR.{Events}
  alias ExNVR.Model.LPREvent

  @moduletag :tmp_dir
  @valid_lpr_event_attributes %{
    plate_number: "01-D-12345",
    direction: "forward",
    list_type: "visitor",
    confidence: 0.7,
    vehicle_type: "Bus",
    vehicle_color: "red",
    plate_color: "white",
    bounding_box: %{
      x1: "0",
      y1: "100",
      x2: "0",
      y2: "50"
    },
    capture_time:
      ~U"2023-12-12T10:00:00Z"
      |> DateTime.to_iso8601()
      |> String.replace("T", " ")
  }
  @lpr_plate_image "../fixtures/images/license-plate.jpg"
                   |> Path.expand(__DIR__)
                   |> File.read!()
                   |> Base.encode64()
  @lpr_full_image "../fixtures/images/license-plate.jpg"
                  |> Path.expand(__DIR__)
                  |> File.read!()
                  |> Base.encode64()

  setup ctx do
    device = device_fixture(%{settings: %{storage_address: ctx.tmp_dir}})
    %{device: device}
  end

  describe "Create events" do
    test "New lpr event", %{device: device} do
      assert {:ok, event} =
               Events.create_lpr_event(
                 device,
                 @valid_lpr_event_attributes,
                 @lpr_plate_image,
                 @lpr_full_image
               )

      assert event
             |> Events.lpr_event_filename()
             |> File.exists?()

      assert event
             |> Events.lpr_event_filename("full_picture")
             |> File.exists?()

      assert event.plate_number == @valid_lpr_event_attributes.plate_number
      assert event.direction == String.to_atom(@valid_lpr_event_attributes.direction)
      assert event.list_type == String.to_atom(@valid_lpr_event_attributes.list_type)
      assert event.confidence == @valid_lpr_event_attributes.confidence
      assert event.vehicle_type == @valid_lpr_event_attributes.vehicle_type
      assert event.vehicle_color == @valid_lpr_event_attributes.vehicle_color
      assert event.plate_color == @valid_lpr_event_attributes.plate_color

      assert event.bounding_box == %LPREvent.BoundingBox{
               x1: String.to_integer(@valid_lpr_event_attributes.bounding_box.x1),
               y1: String.to_integer(@valid_lpr_event_attributes.bounding_box.y1),
               x2: String.to_integer(@valid_lpr_event_attributes.bounding_box.x2),
               y2: String.to_integer(@valid_lpr_event_attributes.bounding_box.y2)
             }

      assert DateTime.compare(
               DateTime.from_iso8601(@valid_lpr_event_attributes.capture_time) |> elem(1),
               event.capture_time
             ) == :eq
    end

    test "plate number is required", %{device: device} do
      params = Map.put(@valid_lpr_event_attributes, :plate_number, nil)

      assert {:error, _} =
               Events.create_lpr_event(
                 device,
                 params,
                 @lpr_plate_image,
                 @lpr_full_image
               )
    end

    test "invalid direction", %{device: device} do
      params = Map.put(@valid_lpr_event_attributes, :direction, "side")

      assert {:error, _} =
               Events.create_lpr_event(
                 device,
                 params,
                 @lpr_plate_image,
                 @lpr_full_image
               )
    end

    test "invalid list type", %{device: device} do
      params = Map.put(@valid_lpr_event_attributes, :list_type, "grey")

      assert {:error, _} =
               Events.create_lpr_event(
                 device,
                 params,
                 @lpr_plate_image,
                 @lpr_full_image
               )
    end
  end

  describe "Get" do
    setup %{device: device} = ctx do
      event = lpr_event_fixture(device)

      Map.put(ctx, :event, event)
    end

    test "Get lpr events", %{device: device} do
      assert length(Events.list(device.id, :lpr)) > 0
    end
  end
end
