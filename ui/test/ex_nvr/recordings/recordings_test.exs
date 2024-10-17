defmodule ExNVR.RecordingTest do
  @moduledoc false

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
                size: 292_713,
                track_details: [
                  track = %{
                    type: :video,
                    media: :h264,
                    media_tag: :avc1,
                    width: 480,
                    height: 240
                  }
                ]
              }} = Recordings.details(device, recording)

      assert ExMP4.Track.bitrate(track) == 465_555
      assert ExMP4.Track.fps(track) == 30.0
    end

    test "get details of not existing recording", %{device: device} do
      assert {:error, :enoent} =
               Recordings.details(device, %Recording{
                 start_date: DateTime.utc_now(),
                 filename: "233434.mp4"
               })
    end
  end

  describe "get snapshot from recording" do
    setup %{device: device} do
      avc_recording =
        recording_fixture(device,
          start_date: ~U(2023-06-23 10:00:00Z),
          end_date: ~U(2023-06-23 10:00:05Z)
        )

      hevc_recording =
        recording_fixture(device,
          start_date: ~U(2023-06-23 10:00:10Z),
          end_date: ~U(2023-06-23 10:00:15Z),
          encoding: :H265
        )

      %{avc_recording: avc_recording, hevc_recording: hevc_recording}
    end

    test "get snapshot from closest keyframe before specified date time", ctx do
      perform_snapshot_test(
        ctx.device,
        ctx.avc_recording,
        ref_path(:h264, "before-keyframe"),
        ~U(2023-06-23 10:00:03Z),
        ~U(2023-06-23 10:00:02Z),
        :before
      )

      perform_snapshot_test(
        ctx.device,
        ctx.hevc_recording,
        ref_path(:h265, "before-keyframe"),
        ~U(2023-06-23 10:00:13Z),
        ~U(2023-06-23 10:00:12Z),
        :before
      )
    end

    test "get snapshot at the provided date time", ctx do
      perform_snapshot_test(
        ctx.device,
        ctx.avc_recording,
        ref_path(:h264, "precise"),
        ~U(2023-06-23 10:00:03Z),
        ~U(2023-06-23 10:00:03Z),
        :precise
      )

      perform_snapshot_test(
        ctx.device,
        ctx.hevc_recording,
        ref_path(:h265, "precise"),
        ~U(2023-06-23 10:00:13Z),
        ~U(2023-06-23 10:00:13Z),
        :precise
      )
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

  defp perform_snapshot_test(
         device,
         recording,
         ref_path,
         requested_datetime,
         snapshot_timestamp,
         method
       ) do
    assert {:ok, timestamp, snapshot} =
             Recordings.snapshot(device, recording, requested_datetime, method: method)

    assert snapshot == File.read!(ref_path)

    assert_in_delta(
      DateTime.to_unix(timestamp, :millisecond),
      DateTime.to_unix(snapshot_timestamp, :millisecond),
      100
    )
  end

  defp ref_path(encoding, method) do
    Path.expand("../../fixtures/images/#{encoding}/ref-#{method}.jpeg", __DIR__)
  end
end
