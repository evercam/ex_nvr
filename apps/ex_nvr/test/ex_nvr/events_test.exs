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

  describe "Create events" do
    test "require plate number and capture time", ctx do
      {:error, changeset} = Events.create_lpr_event(ctx.device, %{}, nil)

      assert %{plate_number: ["can't be blank"], capture_time: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "validate bounding box", ctx do
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

    test "create a new event", ctx do
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

    test "create a new event with plate image", ctx do
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
end
