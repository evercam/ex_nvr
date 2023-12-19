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
      run_fixture(device,
        start_date: run1_start_date,
        end_date: DateTime.add(run1_start_date, 40 * 60)
      )

    run_2 =
      run_fixture(device,
        start_date: run2_start_date,
        end_date: DateTime.add(run2_start_date, 10 * 60)
      )

    recordings_1 =
      Enum.map(
        1..40,
        &recording_fixture(device,
          start_date: DateTime.add(run1_start_date, &1 - 1, :minute),
          end_date: DateTime.add(run1_start_date, &1, :minute),
          run: run_1
        )
      )

    recordings_2 =
      Enum.map(
        1..10,
        &recording_fixture(device,
          start_date: DateTime.add(run2_start_date, &1 - 1, :minute),
          end_date: DateTime.add(run2_start_date, &1, :minute),
          run: run_2
        )
      )

    total_recordings = ExNVR.Repo.aggregate(Recording, :count)
    total_runs = ExNVR.Repo.aggregate(Run, :count)

    assert Recordings.delete_oldest_recordings(device, 30) == :ok

    assert ExNVR.Repo.aggregate(Recording, :count) == total_recordings - 30
    assert ExNVR.Repo.aggregate(Run, :count) == total_runs

    assert_run_start_date(device, ~U(2023-12-12 10:30:00Z))
    assert_files_deleted(device, recordings_1, 30)

    assert Recordings.delete_oldest_recordings(device, 15) == :ok
    assert ExNVR.Repo.aggregate(Recording, :count) == total_recordings - 45
    assert ExNVR.Repo.aggregate(Run, :count) == total_runs - 1

    assert_run_start_date(device, ~U(2023-12-12 11:10:00Z))
    assert_files_deleted(device, recordings_1, 40)
    assert_files_deleted(device, recordings_2, 5)
  end

  defp assert_files_deleted(device, recordings, count) do
    recordings_path =
      recordings
      |> Enum.take(count)
      |> Enum.map(&Recordings.recording_path(device, &1))

    refute Enum.any?(recordings_path, &File.exists?/1)
  end

  defp assert_run_start_date(device, date) do
    run = Recordings.list_runs(device_id: device.id) |> List.first()
    assert DateTime.compare(run.start_date, date) == :eq
  end
end
