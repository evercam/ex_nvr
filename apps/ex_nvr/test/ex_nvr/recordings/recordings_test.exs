defmodule ExNVR.RecordingTest do
  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import ExNVR.RecordingsFixtures

  alias ExNVR.Model.{Run, Recording}
  alias ExNVR.Recordings

  @moduletag :tmp_dir

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

    total_recordings = ExNVR.Repo.aggregate(Recording, :count)
    assert Recordings.delete_oldest_recordings(device, 30) == :ok
    assert ExNVR.Repo.aggregate(Recording, :count) == total_recordings - 30

    run = Recordings.list_runs(device_id: device.id) |> List.first()
    assert DateTime.compare(run.start_date, ~U(2023-12-12 10:30:00Z)) == :eq

    refute Enum.any?(
             1..30,
             &File.exists?(
               Recordings.recording_path(device, %{
                 start_date: DateTime.add(run1_start_date, &1 - 1, :minute)
               })
             )
           )

    total_recordings = ExNVR.Repo.aggregate(Recording, :count)
    total_runs = ExNVR.Repo.aggregate(Run, :count)

    assert Recordings.delete_oldest_recordings(device, 15) == :ok
    assert ExNVR.Repo.aggregate(Recording, :count) == total_recordings - 15
    assert ExNVR.Repo.aggregate(Run, :count) == total_runs - 1

    run = Recordings.list_runs(device_id: device.id) |> List.first()
    assert DateTime.compare(run.start_date, ~U(2023-12-12 11:10:00Z)) == :eq

    refute Enum.any?(
      1..40,
      &File.exists?(
        Recordings.recording_path(device, %{
          start_date: DateTime.add(run1_start_date, &1 - 1, :minute)
        })
      )
    )
    refute Enum.any?(
      1..5,
      &File.exists?(
        Recordings.recording_path(device, %{
          start_date: DateTime.add(run2_start_date, &1 - 1, :minute)
        })
      )
    )
  end
end
