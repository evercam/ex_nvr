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

  describe "get recordings details" do
    test "get recording details", %{device: device} do
      recording = recording_fixture(device)

      assert {:ok,
              %{
                duration: 5_000,
                size: 298_854,
                track_details: [
                  %{
                    type: :video,
                    codec: :H264,
                    codec_tag: :avc1,
                    width: 428,
                    height: 240,
                    fps: 30.0,
                    bitrate: 473_458
                  }
                ]
              }} = Recordings.details(device, recording)
    end

    test "get details of not existing recording", %{device: device} do
      assert {:error, :enoent} =
               Recordings.details(device, %Recording{
                 start_date: DateTime.utc_now(),
                 filename: "233434.mp4"
               })
    end
  end

  test "correct run dates", %{device: device} do
    start_date = ~U(2024-07-27 10:10:00.000000Z)
    duration = 150_000_000

    run =
      run_fixture(device,
        start_date: start_date,
        end_date: DateTime.add(start_date, 5, :minute)
      )

    recs =
      Enum.map(0..4, fn idx ->
        recording_fixture(device,
          run_id: run.id,
          start_date: DateTime.add(start_date, idx, :minute),
          end_date: DateTime.add(start_date, idx + 1, :minute)
        )
      end)

    assert updated_run = Recordings.correct_run_dates(device, run, duration)

    assert DateTime.compare(
             updated_run.start_date,
             DateTime.add(run.start_date, duration, :microsecond)
           ) == :eq

    assert DateTime.compare(
             updated_run.end_date,
             DateTime.add(run.end_date, duration, :microsecond)
           ) == :eq

    assert updated_recs = list_recordings(updated_run)

    for {rec, updated_rec} <- Enum.zip(recs, updated_recs) do
      assert DateTime.compare(
               updated_rec.start_date,
               DateTime.add(rec.start_date, duration, :microsecond)
             ) == :eq

      assert DateTime.compare(
               updated_rec.end_date,
               DateTime.add(rec.end_date, duration, :microsecond)
             ) == :eq

      refute File.exists?(Recordings.recording_path(device, rec))
      assert File.exists?(Recordings.recording_path(device, updated_rec))
    end
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

  def list_recordings(run) do
    from(r in Recording, where: r.run_id == ^run.id, order_by: r.start_date)
    |> ExNVR.Repo.all()
  end
end
