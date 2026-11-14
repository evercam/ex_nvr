defmodule ExNVR.Recordings.BackfillerTest do
  @moduledoc false

  use ExNVR.DataCase
  use Mimic

  import ExNVR.{DevicesFixtures, RecordingsFixtures}
  import ExUnit.CaptureLog

  alias ExMP4.Reader
  alias ExNVR.Devices.Cameras.RemoteRecording
  alias ExNVR.Model.{Device, Recording, Run}
  alias ExNVR.Pipeline.Output.Storage
  alias ExNVR.Recordings
  alias ExNVR.Recordings.Backfiller

  @moduletag :tmp_dir

  # 5 seconds video with keyframes at 0, 2 and 4 seconds
  @fixture "test/fixtures/mp4/big_buck_avc.mp4"
  @opts [min_gap: 3, chunk_duration: 2]

  setup %{tmp_dir: tmp_dir} do
    device = camera_device_fixture(tmp_dir)

    # gap between 10:00:05 and 10:00:15
    run_fixture(device, start_date: ~U(2026-10-01 10:00:00Z), end_date: ~U(2026-10-01 10:00:05Z))
    run_fixture(device, start_date: ~U(2026-10-01 10:00:15Z), end_date: ~U(2026-10-01 10:00:20Z))

    %{device: device}
  end

  describe "gaps/4" do
    test "get intervals not covered by runs", %{device: device} do
      run_fixture(device,
        start_date: ~U(2026-10-01 10:00:30Z),
        end_date: ~U(2026-10-01 10:00:40Z)
      )

      # overlapping run
      run_fixture(device,
        start_date: ~U(2026-10-01 10:00:35Z),
        end_date: ~U(2026-10-01 10:00:45Z)
      )

      assert Backfiller.gaps(device, ~U(2026-10-01 09:59:50Z), ~U(2026-10-01 10:01:00Z), 0) == [
               {~U(2026-10-01 09:59:50Z), ~U(2026-10-01 10:00:00.000000Z)},
               {~U(2026-10-01 10:00:05.000000Z), ~U(2026-10-01 10:00:15.000000Z)},
               {~U(2026-10-01 10:00:20.000000Z), ~U(2026-10-01 10:00:30.000000Z)},
               {~U(2026-10-01 10:00:45.000000Z), ~U(2026-10-01 10:01:00Z)}
             ]
    end

    test "ignore gaps less than min gap", %{device: device} do
      run_fixture(device,
        start_date: ~U(2026-10-01 10:00:25Z),
        end_date: ~U(2026-10-01 10:00:30Z)
      )

      assert Backfiller.gaps(device, ~U(2026-10-01 10:00:00Z), ~U(2026-10-01 10:00:30Z), 6) == [
               {~U(2026-10-01 10:00:05.000000Z), ~U(2026-10-01 10:00:15.000000Z)}
             ]
    end

    test "range without runs", %{device: device} do
      assert Backfiller.gaps(device, ~U(2026-10-02 10:00:00Z), ~U(2026-10-02 11:00:00Z), 0) == [
               {~U(2026-10-02 10:00:00Z), ~U(2026-10-02 11:00:00Z)}
             ]
    end
  end

  describe "fillable_intervals/4" do
    test "merge contiguous camera recordings", %{device: device} do
      stub_camera([
        camera_recording("1", ~U(2026-10-01 10:00:05Z), ~U(2026-10-01 10:00:08Z)),
        # 1 second hole
        camera_recording("2", ~U(2026-10-01 10:00:09Z), ~U(2026-10-01 10:00:12Z)),
        camera_recording("3", ~U(2026-10-01 10:00:12Z), ~U(2026-10-01 10:00:15Z))
      ])

      assert {:ok, intervals} =
               Backfiller.fillable_intervals(
                 device,
                 ~U(2026-10-01 10:00:00Z),
                 ~U(2026-10-01 10:00:20Z),
                 3
               )

      assert truncate(intervals) == [{~U(2026-10-01 10:00:05Z), ~U(2026-10-01 10:00:15Z)}]
    end

    test "intersect camera footage with nvr gaps", %{device: device} do
      stub_camera([camera_recording("1", ~U(2026-10-01 09:59:55Z), ~U(2026-10-01 10:00:25Z))])

      assert {:ok, intervals} =
               Backfiller.fillable_intervals(
                 device,
                 ~U(2026-10-01 09:59:00Z),
                 ~U(2026-10-01 10:01:00Z),
                 3
               )

      assert truncate(intervals) == [
               {~U(2026-10-01 09:59:55Z), ~U(2026-10-01 10:00:00Z)},
               {~U(2026-10-01 10:00:05Z), ~U(2026-10-01 10:00:15Z)},
               {~U(2026-10-01 10:00:20Z), ~U(2026-10-01 10:00:25Z)}
             ]
    end

    test "camera footage is clamped to the requested period", %{device: device} do
      stub_camera([camera_recording("1", ~U(2026-10-01 09:59:55Z), ~U(2026-10-01 10:00:25Z))])

      assert {:ok, intervals} =
               Backfiller.fillable_intervals(
                 device,
                 ~U(2026-10-01 10:00:00Z),
                 ~U(2026-10-01 10:00:22Z),
                 0
               )

      assert truncate(intervals) == [
               {~U(2026-10-01 10:00:05Z), ~U(2026-10-01 10:00:15Z)},
               {~U(2026-10-01 10:00:20Z), ~U(2026-10-01 10:00:22Z)}
             ]
    end

    test "min gap applies to the intersection", %{device: device} do
      stub_camera([camera_recording("1", ~U(2026-10-01 10:00:05Z), ~U(2026-10-01 10:00:08Z))])

      assert {:ok, []} =
               Backfiller.fillable_intervals(
                 device,
                 ~U(2026-10-01 10:00:00Z),
                 ~U(2026-10-01 10:00:20Z),
                 5
               )
    end

    test "list camera recordings once for the whole period", %{device: device} do
      start_date = ~U(2026-10-01 10:00:00Z)
      end_date = ~U(2026-10-01 10:00:20Z)

      expect(ExNVR.Devices, :list_camera_recordings, 1, fn _device, ^start_date, ^end_date ->
        {:ok, []}
      end)

      assert {:ok, []} = Backfiller.fillable_intervals(device, start_date, end_date, 0)
      verify!()
    end

    test "end date is clamped to now", %{device: device} do
      expect(ExNVR.Devices, :list_camera_recordings, fn _device, _start, end_date ->
        assert DateTime.compare(end_date, DateTime.utc_now()) != :gt
        {:ok, []}
      end)

      assert {:ok, []} =
               Backfiller.fillable_intervals(
                 device,
                 DateTime.add(DateTime.utc_now(), -60),
                 DateTime.add(DateTime.utc_now(), 3_600),
                 0
               )
    end

    test "return list error", %{device: device} do
      stub(ExNVR.Devices, :list_camera_recordings, fn _device, _start, _end ->
        {:error, :not_implemented}
      end)

      assert {:error, :not_implemented} =
               Backfiller.fillable_intervals(
                 device,
                 ~U(2026-10-01 10:00:00Z),
                 ~U(2026-10-01 10:00:20Z),
                 0
               )
    end
  end

  describe "run/4" do
    test "fill gap with chunks from camera recordings", %{device: device} do
      stub_camera([
        camera_recording("1", ~U(2026-10-01 10:00:05Z)),
        camera_recording("2", ~U(2026-10-01 10:00:10Z))
      ])

      assert {:ok, [%Run{active: false} = run]} =
               Backfiller.run(device, ~U(2026-10-01 10:00:00Z), ~U(2026-10-01 10:00:20Z), @opts)

      assert run.start_date == ~U(2026-10-01 10:00:05.000000Z)
      assert run.end_date == ~U(2026-10-01 10:00:15.000000Z)

      recordings = backfilled_recordings(device, run)

      assert Enum.map(recordings, &{&1.start_date, &1.end_date}) == [
               {~U(2026-10-01 10:00:05.000000Z), ~U(2026-10-01 10:00:07.000000Z)},
               {~U(2026-10-01 10:00:07.000000Z), ~U(2026-10-01 10:00:09.000000Z)},
               {~U(2026-10-01 10:00:09.000000Z), ~U(2026-10-01 10:00:10.000000Z)},
               {~U(2026-10-01 10:00:10.000000Z), ~U(2026-10-01 10:00:12.000000Z)},
               {~U(2026-10-01 10:00:12.000000Z), ~U(2026-10-01 10:00:14.000000Z)},
               {~U(2026-10-01 10:00:14.000000Z), ~U(2026-10-01 10:00:15.000000Z)}
             ]

      for recording <- recordings do
        assert_recording_file(device, recording, run)
      end

      assert File.ls!(Path.join(Device.base_dir(device), "tmp")) == []
    end

    test "footage is clamped to the gap", %{device: device} do
      stub_camera([
        camera_recording("1", ~U(2026-10-01 10:00:03Z)),
        camera_recording("2", ~U(2026-10-01 10:00:12Z))
      ])

      assert {:ok, [run1, run2]} =
               Backfiller.run(device, ~U(2026-10-01 10:00:00Z), ~U(2026-10-01 10:00:20Z), @opts)

      # first keyframe after gap start is at 10:00:05
      assert Enum.map(backfilled_recordings(device, run1), &{&1.start_date, &1.end_date}) == [
               {~U(2026-10-01 10:00:05.000000Z), ~U(2026-10-01 10:00:07.000000Z)},
               {~U(2026-10-01 10:00:07.000000Z), ~U(2026-10-01 10:00:08.000000Z)}
             ]

      assert Enum.map(backfilled_recordings(device, run2), &{&1.start_date, &1.end_date}) == [
               {~U(2026-10-01 10:00:12.000000Z), ~U(2026-10-01 10:00:14.000000Z)},
               {~U(2026-10-01 10:00:14.000000Z), ~U(2026-10-01 10:00:15.000000Z)}
             ]
    end

    test "overlapping camera recordings do not create overlapping chunks", %{device: device} do
      stub_camera([
        camera_recording("1", ~U(2026-10-01 10:00:05Z)),
        camera_recording("2", ~U(2026-10-01 10:00:07Z))
      ])

      assert {:ok, [run]} =
               Backfiller.run(device, ~U(2026-10-01 10:00:00Z), ~U(2026-10-01 10:00:20Z), @opts)

      assert Enum.map(backfilled_recordings(device, run), &{&1.start_date, &1.end_date}) == [
               {~U(2026-10-01 10:00:05.000000Z), ~U(2026-10-01 10:00:07.000000Z)},
               {~U(2026-10-01 10:00:07.000000Z), ~U(2026-10-01 10:00:09.000000Z)},
               {~U(2026-10-01 10:00:09.000000Z), ~U(2026-10-01 10:00:10.000000Z)},
               {~U(2026-10-01 10:00:11.000000Z), ~U(2026-10-01 10:00:12.000000Z)}
             ]
    end

    test "skip camera recordings that fail to download", %{device: device} do
      stub_camera([
        camera_recording("1", ~U(2026-10-01 10:00:05Z)),
        camera_recording("2", ~U(2026-10-01 10:00:10Z))
      ])

      stub(ExNVR.Devices, :download_camera_recording, fn
        _device, %{id: "1"}, _dest -> {:error, :timeout}
        _device, _rec, dest -> File.cp(@fixture, dest)
      end)

      assert capture_log(fn ->
               assert {:ok, [run]} =
                        Backfiller.run(
                          device,
                          ~U(2026-10-01 10:00:00Z),
                          ~U(2026-10-01 10:00:20Z),
                          @opts
                        )

               assert {run.start_date, run.end_date} ==
                        {~U(2026-10-01 10:00:10.000000Z), ~U(2026-10-01 10:00:15.000000Z)}
             end) =~ "skip camera recording 1"
    end

    test "return error when vendor is not supported", %{device: device} do
      stub(ExNVR.Devices, :list_camera_recordings, fn _device, _start, _end ->
        {:error, :not_implemented}
      end)

      assert {:error, :not_implemented} =
               Backfiller.run(device, ~U(2026-10-01 10:00:00Z), ~U(2026-10-01 10:00:20Z), @opts)
    end
  end

  defp camera_recording(id, start_date, end_date \\ nil) do
    %RemoteRecording{
      id: id,
      start_date: start_date,
      end_date: end_date || DateTime.add(start_date, 5),
      type: :schedule
    }
  end

  defp stub_camera(camera_recordings) do
    stub(ExNVR.Devices, :list_camera_recordings, fn _device, start_date, end_date ->
      {:ok, overlapping(camera_recordings, start_date, end_date)}
    end)

    stub(ExNVR.Devices, :download_camera_recording, fn _device, _rec, dest ->
      File.cp(@fixture, dest)
    end)
  end

  defp overlapping(camera_recordings, start_date, end_date) do
    Enum.filter(
      camera_recordings,
      &(DateTime.before?(&1.start_date, end_date) and DateTime.after?(&1.end_date, start_date))
    )
  end

  # ignore datetime precision
  defp truncate(intervals) do
    Enum.map(intervals, fn {start_date, end_date} ->
      {DateTime.truncate(start_date, :second), DateTime.truncate(end_date, :second)}
    end)
  end

  defp backfilled_recordings(device, run) do
    Recording
    |> where([r], r.device_id == ^device.id and r.run_id == ^run.id)
    |> order_by(asc: :start_date)
    |> Repo.all()
  end

  defp assert_recording_file(device, recording, run) do
    path = Recordings.recording_path(device, recording)
    reader = Reader.new!(path)

    assert %{data: data} = Enum.find(reader.uuid, &(&1.type == Storage.metadata_uuid()))
    assert %{"run_id" => run_id} = Jason.decode!(data)
    assert run_id == run.id

    expected_duration = DateTime.diff(recording.end_date, recording.start_date, :millisecond)
    assert Reader.duration(reader) == expected_duration

    Reader.close(reader)
  end
end
