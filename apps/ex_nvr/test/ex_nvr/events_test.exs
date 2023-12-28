defmodule ExNVR.EventsTest do
  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import ExNVR.RecordingsFixtures

  alias ExNVR.{Events}

  @moduletag :tmp_dir
  @lpr_event_paramerters %{
    "plate" => "sfdsfd",
    "direction" => "forward",
    "plate_image" => ""
  }

  setup ctx do
    device = device_fixture(%{settings: %{storage_address: ctx.tmp_dir}})
    %{device: device}
  end

  describe "Create" do
    test "Create lpr events", %{device: device} do
      assert {:ok, event} = Events.create(
        @lpr_event_paramerters,
        device,
        :lpr
      )

      file_path =
        event
        |> Events.base_dir(device)
        |> Path.join("#{event.plate_number}_#{event.id}.jpg")

      assert File.exists?(file_path)
    end
  end
end
