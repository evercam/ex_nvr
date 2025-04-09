defmodule ExNVR.EventsTest do
  use ExNVR.DataCase

  import ExNVR.DevicesFixtures

  alias ExNVR.Events
  alias ExNVR.Model.Device

  @moduletag :tmp_dir

  @valid_plate_number "FC-546-15"
  @valid_capture_time "2024-01-31T15:00:00Z"

  @lpr_plate_image "test/fixtures/images/license-plate.jpg"

  setup ctx do
    %{device: camera_device_fixture(ctx.tmp_dir)}
  end

  describe "Create LPR events" do
    test "require LPR plate number and capture time", ctx do
      {:error, changeset} = Events.create_lpr_event(ctx.device, %{}, nil)

      assert %{plate_number: ["can't be blank"], capture_time: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "validate LPR event bounding box", ctx do
      event = %{
        plate_number: @valid_plate_number,
        capture_time: @valid_capture_time,
        metadata: %{bounding_box: [0.1, 0.3]}
      }

      {:error, changeset} = Events.create_lpr_event(ctx.device, event, nil)
      assert %{metadata: %{bounding_box: ["array must have 4 values"]}} = errors_on(changeset)

      {:error, changeset} =
        Events.create_lpr_event(
          ctx.device,
          put_in(event, [:metadata, :bounding_box], [0.1, 0.2, 1.1, -0.1]),
          nil
        )

      assert %{metadata: %{bounding_box: ["all values must be in the range [0..1]"]}} =
               errors_on(changeset)
    end

    test "create a new LPR event", ctx do
      event = %{
        plate_number: @valid_plate_number,
        capture_time: @valid_capture_time,
        list_type: :white,
        metadata: %{bounding_box: [0.1, 0.3, 0.15, 0.36]}
      }

      {:ok, event} = Events.create_lpr_event(ctx.device, event, nil)

      assert event.plate_number == @valid_plate_number
      assert event.capture_time == ~U(2024-01-31 15:00:00.000000Z)
      assert event.direction == :unknown
      assert %{bounding_box: [0.1, 0.3, 0.15, 0.36]} = event.metadata
    end

    test "create a new LPR event with plate image", ctx do
      event = %{
        plate_number: @valid_plate_number,
        capture_time: @valid_capture_time,
        list_type: :white,
        metadata: %{bounding_box: [0.1, 0.3, 0.15, 0.36]}
      }

      {:ok, event} = Events.create_lpr_event(ctx.device, event, File.read!(@lpr_plate_image))

      assert Device.lpr_thumbnails_dir(ctx.device)
             |> Path.join(Events.LPR.plate_name(event))
             |> File.exists?()
    end
  end

  describe "create generic events" do
    test "create a generic event", %{device: device} do
      event_data = %{"location" => "server room", "temperature" => 42}
      params = %{"event_type" => "temperature_alert"}

      {:ok, event} = Events.create_event(device, params, event_data)

      assert event.device_id == device.id
      assert event.event_type == "temperature_alert"
      assert event.event_data == event_data
    end

    test "assign a default timestamp when no event_time is provided", %{device: device} do
      params = %{
        "event_type" => "intrusion"
      }

      before = DateTime.utc_now()
      {:ok, event} = Events.create_event(device, params)
      after_ = DateTime.utc_now()

      assert DateTime.compare(event.event_time, before) != :lt
      assert DateTime.compare(event.event_time, after_) != :gt
    end

    test "assign an empty json when no event_data is provided", %{device: device} do
      params = %{
        "event_type" => "door_open"
      }

      {:ok, event} = Events.create_event(device, params)
      assert event.event_data == %{}
    end

    test "reject invalid event_data JSON", %{device: device} do
      params = %{"event_type" => "cosmic_rays_exposure"}
      invalid_data = %{"value" => {:a, :b}}

      {:error, changeset} = Events.create_event(device, params, invalid_data)

      assert %{event_data: ["must be JSON serializable"]} = errors_on(changeset)
    end
  end
end
