defmodule ExNVR.RecordingTest do
  use ExNVR.DataCase

  import ExNVR.DevicesFixtures
  import ExNVR.RecordingsFixtures

  alias ExNVR.Model.{Run, Recording}
  alias ExNVR.Recordings

  @moduletag :tmp_dir

  setup ctx do
    %{device: camera_device_fixture(ctx.tmp_dir)}
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

    low_res_run_1 =
      run_fixture(device,
        start_date: DateTime.add(run1_start_date, 5),
        end_date: DateTime.add(run1_start_date, 40 * 60 + 5),
        stream: :low
      )

    low_res_run_2 =
      run_fixture(device,
        start_date: DateTime.add(run2_start_date, 5),
        end_date: DateTime.add(run2_start_date, 10 * 60 + 5),
        stream: :low
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

    low_res_recordings_1 =
      Enum.map(
        1..40,
        &recording_fixture(device,
          start_date: DateTime.add(run1_start_date, &1 * 60 - 55, :second),
          end_date: DateTime.add(run1_start_date, &1 * 60 + 5, :second),
          run: low_res_run_1,
          stream: :low
        )
      )

    low_res_recordings_2 =
      Enum.map(
        1..10,
        &recording_fixture(device,
          start_date: DateTime.add(run2_start_date, &1 * 60 - 55, :second),
          end_date: DateTime.add(run2_start_date, &1 * 60 + 5, :second),
          run: low_res_run_2,
          stream: :low
        )
      )

    total_recordings = ExNVR.Repo.aggregate(Recording, :count)
    total_runs = ExNVR.Repo.aggregate(Run, :count)

    assert Recordings.delete_oldest_recordings(device, 30) == :ok

    assert ExNVR.Repo.aggregate(Recording, :count) == total_recordings - 59
    assert ExNVR.Repo.aggregate(Run, :count) == total_runs

    assert_run_start_date(device, :high, ~U(2023-12-12 10:30:00Z))
    assert_run_start_date(device, :low, ~U(2023-12-12 10:29:05Z))

    assert_files_deleted(device, :high, recordings_1, 30)
    assert_files_deleted(device, :low, low_res_recordings_1, 29)

    assert Recordings.delete_oldest_recordings(device, 15) == :ok
    assert ExNVR.Repo.aggregate(Recording, :count) == total_recordings - 89
    assert ExNVR.Repo.aggregate(Run, :count) == total_runs - 2

    assert_run_start_date(device, :high, ~U(2023-12-12 11:10:00Z))
    assert_run_start_date(device, :low, ~U(2023-12-12 11:09:05Z))

    assert_files_deleted(device, :high, recordings_1, 40)
    assert_files_deleted(device, :low, low_res_recordings_1, 40)
    assert_files_deleted(device, :high, recordings_2, 5)
    assert_files_deleted(device, :high, low_res_recordings_2, 4)
  end

  defp assert_files_deleted(device, stream_type, recordings, count) do
    recordings_path =
      recordings
      |> Enum.take(count)
      |> Enum.map(&Recordings.recording_path(device, stream_type, &1))

    refute Enum.any?(recordings_path, &File.exists?/1)
  end

  defp assert_run_start_date(device, stream_type, date) do
    run = Recordings.list_runs([device_id: device.id], stream_type) |> List.first()
    assert DateTime.compare(run.start_date, date) == :eq
  end
end
