defmodule ExNVR.Export.WorkerTest do
  use ExNVR.DataCase

  alias ExNVR.Export

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    device = camera_device_fixture(tmp_dir)
    %{device: device, dest_dir: Path.join(tmp_dir, "export_output")}
  end

  defp contiguous_recordings(device) do
    for offset <- [0, 5, 10] do
      start_date = DateTime.add(~U(2024-12-15T11:00:00.000000Z), offset)

      recording_fixture(device,
        start_date: start_date,
        end_date: DateTime.add(start_date, 5)
      )
    end
  end

  defp wait_until(fun, attempts \\ 200)

  defp wait_until(_fun, 0), do: flunk("condition not met in time")

  defp wait_until(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      wait_until(fun, attempts - 1)
    end
  end

  defp wait_completed(dest_dir) do
    wait_until(fn ->
      match?(
        {:ok, %{status: status}} when status in [:completed, :failed],
        Export.progress(dest_dir)
      )
    end)

    Export.progress(dest_dir)
  end

  defp start_delayed(device, stream, start_date, end_date, dest_dir, opts) do
    args = [
      device: device,
      stream: stream,
      start_date: start_date,
      end_date: end_date,
      dest_dir: Path.expand(dest_dir),
      max_duration: opts[:max_duration],
      max_file_size: opts[:max_file_size],
      tick_delay: 30,
      notify: self()
    ]

    DynamicSupervisor.start_child(ExNVR.Export.Supervisor, {ExNVR.Export.Worker, args})
  end

  test "exports a full range into a single file", %{device: device, dest_dir: dest_dir} do
    contiguous_recordings(device)

    assert {:ok, _pid} =
             Export.start(
               device,
               :high,
               ~U(2024-12-15T11:00:00Z),
               ~U(2024-12-15T11:00:15Z),
               dest_dir
             )

    assert {:ok, %{status: :completed, files: [file]}} = wait_completed(dest_dir)
    assert {:ok, reader} = ExMP4.Reader.new(Path.join(dest_dir, file.filename))
    assert ExMP4.Reader.duration(reader, :millisecond) == 15_000
  end

  test "splits output by max_duration on keyframe boundaries", %{
    device: device,
    dest_dir: dest_dir
  } do
    contiguous_recordings(device)

    assert {:ok, _pid} =
             Export.start(
               device,
               :high,
               ~U(2024-12-15T11:00:00Z),
               ~U(2024-12-15T11:00:15Z),
               dest_dir,
               max_duration: 5
             )

    assert {:ok, %{status: :completed, files: files}} = wait_completed(dest_dir)
    assert length(files) == 3
    assert Enum.all?(files, &(DateTime.diff(&1.end_date, &1.start_date) == 5))

    total_ms =
      Enum.reduce(files, 0, fn file, acc ->
        {:ok, reader} = ExMP4.Reader.new(Path.join(dest_dir, file.filename))
        acc + ExMP4.Reader.duration(reader, :millisecond)
      end)

    assert total_ms == 15_000
  end

  test "splits output by max_file_size on keyframe boundaries", %{
    device: device,
    dest_dir: dest_dir
  } do
    recording_fixture(device,
      start_date: ~U(2024-12-15T11:00:00Z),
      end_date: ~U(2024-12-15T11:00:05Z)
    )

    assert {:ok, _pid} =
             Export.start(
               device,
               :high,
               ~U(2024-12-15T11:00:00Z),
               ~U(2024-12-15T11:00:05Z),
               dest_dir,
               max_file_size: 120_000
             )

    assert {:ok, %{status: :completed, files: [file1, file2]}} = wait_completed(dest_dir)
    assert DateTime.diff(file1.end_date, file1.start_date) == 4
    assert DateTime.diff(file2.end_date, file2.start_date) == 1
    assert file1.size >= 120_000
  end

  test "resumes after the worker is killed mid-file, with no duplicated frames at the seam", %{
    device: device,
    dest_dir: dest_dir
  } do
    contiguous_recordings(device)
    dest_dir = Path.expand(dest_dir)

    assert {:ok, pid} =
             start_delayed(
               device,
               :high,
               ~U(2024-12-15T11:00:00Z),
               ~U(2024-12-15T11:00:15Z),
               dest_dir,
               max_duration: 5
             )

    assert_receive {:export_tick, ^dest_dir, 1}, 2000

    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

    assert {:ok, manifest} = ExNVR.Export.Manifest.load(dest_dir)
    assert length(manifest.files) == 1
    assert manifest.status == :running

    stray_path = Path.join(dest_dir, "export_00001.mp4")
    assert File.exists?(stray_path)
    assert {:ok, %{tracks: nil}} = ExMP4.Reader.new(stray_path)

    assert {:ok, _pid} =
             Export.start(
               device,
               :high,
               ~U(2024-12-15T11:00:00Z),
               ~U(2024-12-15T11:00:15Z),
               dest_dir,
               max_duration: 5
             )

    assert {:ok, %{status: :completed, files: files}} = wait_completed(dest_dir)
    assert length(files) == 3

    total_ms =
      Enum.reduce(files, 0, fn file, acc ->
        {:ok, reader} = ExMP4.Reader.new(Path.join(dest_dir, file.filename))
        acc + ExMP4.Reader.duration(reader, :millisecond)
      end)

    assert total_ms == 15_000
  end

  test "stop/1 pauses the job and start/6 resumes it", %{device: device, dest_dir: dest_dir} do
    contiguous_recordings(device)
    dest_dir = Path.expand(dest_dir)

    assert {:ok, _pid} =
             start_delayed(
               device,
               :high,
               ~U(2024-12-15T11:00:00Z),
               ~U(2024-12-15T11:00:15Z),
               dest_dir,
               max_duration: 5
             )

    assert_receive {:export_tick, ^dest_dir, 1}, 2000
    assert :ok = Export.stop(dest_dir)

    assert {:ok, %{status: :paused, files: [_ | _]}} = Export.progress(dest_dir)

    assert {:ok, _pid} =
             Export.start(
               device,
               :high,
               ~U(2024-12-15T11:00:00Z),
               ~U(2024-12-15T11:00:15Z),
               dest_dir,
               max_duration: 5
             )

    assert {:ok, %{status: :completed, files: files}} = wait_completed(dest_dir)

    assert Enum.zip(files, tl(files))
           |> Enum.all?(fn {a, b} -> DateTime.compare(a.end_date, b.start_date) == :eq end)

    total_ms =
      Enum.reduce(files, 0, fn file, acc ->
        {:ok, reader} = ExMP4.Reader.new(Path.join(dest_dir, file.filename))
        acc + ExMP4.Reader.duration(reader, :millisecond)
      end)

    assert total_ms == 15_000
  end

  test "start/6 refuses to restart an already-completed job", %{
    device: device,
    dest_dir: dest_dir
  } do
    contiguous_recordings(device)

    assert {:ok, _pid} =
             Export.start(
               device,
               :high,
               ~U(2024-12-15T11:00:00Z),
               ~U(2024-12-15T11:00:15Z),
               dest_dir
             )

    assert {:ok, %{status: :completed}} = wait_completed(dest_dir)

    assert {:error, {:already_completed, manifest}} =
             Export.start(
               device,
               :high,
               ~U(2024-12-15T11:00:00Z),
               ~U(2024-12-15T11:00:15Z),
               dest_dir
             )

    assert manifest.status == :completed
  end

  test "fails with :no_recordings when the range is empty", %{device: device, dest_dir: dest_dir} do
    assert {:ok, _pid} =
             Export.start(
               device,
               :high,
               ~U(2024-12-15T11:00:00Z),
               ~U(2024-12-15T11:00:15Z),
               dest_dir
             )

    assert {:ok, %{status: :failed, error: "no_recordings", files: []}} = wait_completed(dest_dir)
  end

  test "fails with :codec_changed and keeps files produced before the change", %{
    device: device,
    dest_dir: dest_dir
  } do
    recording_fixture(device,
      start_date: ~U(2024-12-15T11:00:00Z),
      end_date: ~U(2024-12-15T11:00:05Z),
      encoding: :H264
    )

    recording_fixture(device,
      start_date: ~U(2024-12-15T11:00:05Z),
      end_date: ~U(2024-12-15T11:00:10Z),
      encoding: :H265
    )

    assert {:ok, _pid} =
             Export.start(
               device,
               :high,
               ~U(2024-12-15T11:00:00Z),
               ~U(2024-12-15T11:00:10Z),
               dest_dir
             )

    assert {:ok, %{status: :failed, error: "codec_changed", files: [file]}} =
             wait_completed(dest_dir)

    assert {:ok, _reader} = ExMP4.Reader.new(Path.join(dest_dir, file.filename))
  end

  test "progress/1 falls back to the on-disk manifest once the worker has exited", %{
    device: device,
    dest_dir: dest_dir
  } do
    contiguous_recordings(device)

    assert {:ok, _pid} =
             Export.start(
               device,
               :high,
               ~U(2024-12-15T11:00:00Z),
               ~U(2024-12-15T11:00:15Z),
               dest_dir
             )

    assert {:ok, %{status: :completed}} = wait_completed(dest_dir)
    assert Registry.lookup(ExNVR.Export.Registry, Path.expand(dest_dir)) == []
    assert {:ok, %{status: :completed, percentage: 100.0}} = Export.progress(dest_dir)
  end
end
