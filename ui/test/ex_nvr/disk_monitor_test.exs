defmodule ExNVR.DiskMonitorTest do
  @moduledoc false

  use ExNVR.DataCase

  alias ExNVR.DiskMonitor
  alias ExNVR.Model.Recording

  @moduletag :tmp_dir

  # init/1 sends an initial tick, so 5 more ticks are
  # needed to reach the delete threshold (ticks_until_delete)
  @remaining_ticks_until_delete 5

  setup ctx do
    %{device: camera_device_fixture(ctx.tmp_dir)}
  end

  test "delete oldest recordings when drive is nearly full", %{device: device} do
    start_date = ~U(2023-12-12 10:00:00Z)

    run =
      run_fixture(device,
        start_date: start_date,
        end_date: DateTime.add(start_date, 5 * 60)
      )

    Enum.each(
      1..5,
      &recording_fixture(device,
        start_date: DateTime.add(start_date, &1 - 1, :minute),
        end_date: DateTime.add(start_date, &1, :minute),
        run: run
      )
    )

    pid = start_disk_monitor(device)
    Enum.each(1..@remaining_ticks_until_delete, fn _idx -> send(pid, :tick) end)

    # synchronize with the monitor to make sure all ticks were handled
    assert %{full_space_ticks: 0} = :sys.get_state(pid)
    assert Repo.aggregate(Recording, :count) == 0
  end

  test "does not crash when the device has no recordings", %{device: device} do
    pid = start_disk_monitor(device)
    Enum.each(1..@remaining_ticks_until_delete, fn _idx -> send(pid, :tick) end)

    assert %{full_space_ticks: 0} = :sys.get_state(pid)
    assert Process.alive?(pid)
  end

  defp start_disk_monitor(device) do
    start_supervised!({DiskMonitor, device: device, disk_usage_fun: fn _device -> 100 end})
  end
end
