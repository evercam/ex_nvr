defmodule ExNVR.Recordings.BackfillJobTest do
  @moduledoc false

  use ExNVR.DataCase
  use Mimic

  import ExNVR.DevicesFixtures
  import ExUnit.CaptureLog

  alias ExNVR.Model.Run
  alias ExNVR.Recordings.{Backfiller, BackfillJob}

  @moduletag :tmp_dir

  # the job runs under a supervisor, not in the test process
  setup :set_mimic_global

  setup %{tmp_dir: tmp_dir} do
    device = camera_device_fixture(tmp_dir)
    Phoenix.PubSub.subscribe(ExNVR.PubSub, BackfillJob.topic(device.id))
    %{device: device}
  end

  test "run a backfill job", %{device: device} do
    test_pid = self()
    run = %Run{start_date: ~U(2026-10-01 10:00:00Z), end_date: ~U(2026-10-01 10:01:00Z)}

    expect(Backfiller, :run, fn ^device, _start_date, _end_date, opts ->
      send(test_pid, {:running, self(), opts})
      receive do: (:finish -> {:ok, [run]})
    end)

    assert is_nil(BackfillJob.status(device))
    assert {:ok, pid} = BackfillJob.start(device, 5)
    assert_receive {:backfill, :started}
    assert_receive {:running, ^pid, [min_gap: 300]}

    assert %{min_gap: 5, started_at: %DateTime{}} = BackfillJob.status(device)
    assert {:error, :already_running} = BackfillJob.start(device, 10)

    ref = Process.monitor(pid)
    capture_log(fn -> send(pid, :finish) end)

    assert_receive {:backfill, {:completed, [^run]}}
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert is_nil(BackfillJob.status(device))
  end

  test "run backfill jobs of different devices concurrently", %{device: device, tmp_dir: tmp_dir} do
    test_pid = self()
    other_device = camera_device_fixture(tmp_dir)

    stub(Backfiller, :run, fn device, _start_date, _end_date, _opts ->
      send(test_pid, {:running, device.id, self()})
      receive do: (:finish -> {:ok, []})
    end)

    assert {:ok, _pid} = BackfillJob.start(device, 10)
    assert {:ok, _pid} = BackfillJob.start(other_device, 10)

    for device_id <- [device.id, other_device.id] do
      assert_receive {:running, ^device_id, pid}
      capture_log(fn -> send(pid, :finish) end)
    end

    assert_receive {:backfill, {:completed, []}}
  end

  test "broadcast failures", %{device: device} do
    expect(Backfiller, :run, fn _device, _start_date, _end_date, _opts ->
      {:error, :not_implemented}
    end)

    capture_log(fn ->
      assert {:ok, _pid} = BackfillJob.start(device, 10)
      assert_receive {:backfill, {:failed, :not_implemented}}
    end)
  end

  test "broadcast exceptions as failures", %{device: device} do
    expect(Backfiller, :run, fn _device, _start_date, _end_date, _opts ->
      raise "camera unreachable"
    end)

    capture_log(fn ->
      assert {:ok, _pid} = BackfillJob.start(device, 10)
      assert_receive {:backfill, {:failed, "camera unreachable"}}
    end)
  end
end
