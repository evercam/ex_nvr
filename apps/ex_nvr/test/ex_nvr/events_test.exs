defmodule ExNVR.EventsTest do
  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import ExNVR.RecordingsFixtures

  alias ExNVR.{Events}

  @moduletag :tmp_dir
  @lpr_plate "01-D-12345"
  @lpr_direction "forward"
  @lpr_time ~U"2023-12-12T10:00:00Z"
  @lpr_plate_image ""

  setup ctx do
    device = device_fixture(%{settings: %{storage_address: ctx.tmp_dir}})
    %{device: device}
  end

  describe "Create" do
    test "Create lpr events", %{device: device} do
      assert {:ok, event} =
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

      file_path =
        event
        |> Events.base_dir(device)
        |> Path.join("#{event.plate_number}_#{event.id}.jpg")

      assert File.exists?(file_path)
      assert event.plate_number == @lpr_plate
      assert event.direction == @lpr_direction

      assert DateTime.compare(@lpr_time, event.capture_time) == :eq
    end
  end
end
