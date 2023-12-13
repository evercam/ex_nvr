defmodule ExNVR.Recordings.SnapshooterTest do
  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import ExNVR.RecordingsFixtures

  alias ExNVR.Recordings

  @moduletag :tmp_dir
  @recordings_range Enum.to_list(0..39)

  setup ctx do
    device = device_fixture(%{settings: %{storage_address: ctx.tmp_dir}})
    %{device: device}
  end

  describe "Multiple recordings" do
    test "delete multiple recordings", %{device: device} do
      start_date = ~U(2023-06-23 10:00:00Z)

      run =
        run_fixture(device, %{
          start_date: start_date,
          end_date:
            DateTime.add(
              start_date,
              List.last(@recordings_range),
              :minute
            )
        })

      recordings =
        Enum.map(@recordings_range, fn value ->
          recording_fixture(device,
            start_date: DateTime.add(start_date, value, :minute),
            end_date: DateTime.add(start_date, value + 1, :minute),
            run: run
          )
        end)

      assert Recordings.delete_oldest_recordings(device, 30) == :ok

      assert length(Recordings.index(device.id)) == 10

      assert :eq ==
               Recordings.list_runs(device_id: device.id)
               |> List.first()
               |> Map.get(:start_date)
               |> DateTime.compare(DateTime.add(start_date, 30, :minute))
    end
  end
end
