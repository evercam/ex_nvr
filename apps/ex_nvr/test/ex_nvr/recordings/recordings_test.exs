defmodule ExNVR.RecordingTest do
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

  test "delete multiple recordings", %{device: device} do
    run1_start_date = ~U(2023-12-12 10:00:00Z)
    run2_start_date = ~U(2023-12-12 11:05:00Z)

    run_1 =
      run_fixture(device, %{
        start_date: run1_start_date,
        end_date:
          DateTime.add(
            run1_start_date,
            40,
            :minute
          )
      })

    run_2 =
      run_fixture(device, %{
        start_date: run2_start_date,
        end_date:
          DateTime.add(
            run2_start_date,
            10,
            :minute
          )
      })

    recordings_1 =
      Enum.map(
        1..40,
        &recording_fixture(
          device,
          start_date: DateTime.add(run1_start_date, &1 - 1, :minute),
          end_date: DateTime.add(run1_start_date, &1, :minute),
          run: run_1
        )
      )

    recordings_1 =
      Enum.map(
        1..10,
        &recording_fixture(
          device,
          start_date: DateTime.add(run2_start_date, &1 - 1, :minute),
          end_date: DateTime.add(run2_start_date, &1, :minute),
          run: run_2
        )
      )

    assert length(Recordings.index(device.id)) == 50
    assert {:ok, recordings} = Recordings.delete_oldest_recordings(device, 30)
    assert length(Recordings.index(device.id)) == 20

    assert :eq ==
             Recordings.list_runs(device_id: device.id)
             |> List.first()
             |> Map.get(:start_date)
             |> DateTime.compare(DateTime.add(run1_start_date, 30, :minute))

    assert !Enum.all?(recordings, &File.exists?(&1.filename))

    assert {:ok, recordings} = Recordings.delete_oldest_recordings(device, 15)
    assert length(Recordings.index(device.id)) == 5
    assert length(Recordings.list_runs(device_id: device.id)) == 1

    assert :eq ==
             Recordings.list_runs(device_id: device.id)
             |> List.first()
             |> Map.get(:start_date)
             |> DateTime.compare(DateTime.add(run2_start_date, 5, :minute))

    assert !Enum.all?(recordings, &File.exists?(&1.filename))
  end
end
