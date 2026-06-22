defmodule ExNVR.QemuTest.WatchdogRebootTest do
  @moduledoc """
  Proves the nvr_support watchdog reboots a booted device for each reboot-worthy
  criterion - storage unwritable, core process unresponsive, and recording
  stalled. Each test drives the live firmware over RPC, induces the fault, and
  observes nerves_heart rebooting the guest as a QMP `RESET` event.
  """
  use ExNVR.QemuTest.QemuCase

  # Mountpoint for the separate recordings disk. Must live under a writable path
  # (/ is the read-only squashfs rootfs); /data is the writable app partition.
  @rec "/data/recordings"

  @tag vm_opts: [data_disk: %{size: "64M"}]
  test "a read-only recordings partition trips the watchdog and reboots the device", %{vm: vm} do
    # Use the data disk (/dev/vdb) as the recordings store and point the watchdog
    # at it with a short window.
    assert {_, 0} =
             VM.cmd(vm, "mkdir -p #{@rec} && mkfs.ext4 -F -q /dev/vdb && mount /dev/vdb #{@rec}")

    :ok = VM.call(vm, Application, :put_env, [:nvr_support, :recordings_path, @rec])
    :ok = VM.call(vm, Application, :put_env, [:nvr_support, :storage_debounce_ms, 3_000])

    # Storage only counts as a fault when a camera is configured to record; the
    # recording state also keeps RecordingStalled from confounding this test.
    :ok = VM.call(vm, Application, :put_env, [:nvr_support, :devices, [%{state: :recording}]])

    # Healthy while the partition accepts writes.
    assert VM.call(vm, NvrSupport.Watchdog.Heart, :check, []) == :ok

    # Make video writes fail: remount the recordings filesystem read-only.
    assert {_, 0} = VM.cmd(vm, "mount -o remount,ro #{@rec}")

    # The watchdog must trip and nerves_heart must reboot the guest.
    assert VM.await_reset(vm, 120_000),
           "device did not reboot after the recordings partition went read-only"
  end

  test "an unresponsive core process trips the watchdog and reboots the device", %{vm: vm} do
    assert VM.call(vm, NvrSupport.Watchdog.Heart, :check, []) == :ok

    # Simulate a wedged/missing core process: point the internal-liveness probe
    # at a loaded module that has no registered process, so it reads as down the
    # way a dead ExNVR.SystemStatus would.
    :ok = VM.call(vm, Application, :put_env, [:nvr_support, :system_status_module, Enum])

    assert VM.await_reset(vm, 120_000),
           "device did not reboot when the core process became unresponsive"
  end

  test "all configured cameras non-recording trips the watchdog and reboots the device",
       %{vm: vm} do
    assert VM.call(vm, NvrSupport.Watchdog.Heart, :check, []) == :ok

    # A configured camera that never reaches :recording = the recording pipeline
    # is wedged. Storage stays healthy at the default tmpfs path.
    :ok = VM.call(vm, Application, :put_env, [:nvr_support, :devices, [%{state: :stopped}]])

    assert VM.await_reset(vm, 120_000),
           "device did not reboot when no configured camera was recording"
  end
end
