defmodule ExNVR.QemuTest.WatchdogSafeguardsTest do
  @moduledoc """
  The watchdog's safeguards - cases where it must NOT reboot: when explicitly
  disabled (kill-switch), when a failing criterion recovers before its debounce
  window qualifies, and when storage is unwritable but no camera is configured
  (nothing to record, so a reboot can't help). Each asserts the absence of a QMP
  RESET within a window comfortably longer than a normal trip-and-reboot.
  """
  use ExNVR.QemuTest.QemuCase

  @rec "/data/recordings"

  # Format/mount the separate recordings disk, point the watchdog at it, and
  # configure a recording camera so the storage criterion is actually in effect.
  defp mount_recordings(vm) do
    assert {_, 0} =
             VM.cmd(vm, "mkdir -p #{@rec} && mkfs.ext4 -F -q /dev/vdb && mount /dev/vdb #{@rec}")

    :ok = VM.call(vm, Application, :put_env, [:nvr_support, :recordings_path, @rec])
    :ok = VM.call(vm, Application, :put_env, [:nvr_support, :devices, [%{state: :recording}]])
  end

  @tag vm_opts: [data_disk: %{size: "64M"}]
  test "the kill-switch prevents a reboot while a criterion is failing", %{vm: vm} do
    mount_recordings(vm)
    :ok = VM.call(vm, Application, :put_env, [:nvr_support, :storage_debounce_ms, 3_000])

    # Disable the watchdog before inducing the fault.
    :ok = VM.call(vm, Nerves.Runtime.KV, :put, ["nvr_support_disable_watchdog", "true"])

    # The alarm will set, but the heart callback stays :ok -> no reboot.
    assert {_, 0} = VM.cmd(vm, "mount -o remount,ro #{@rec}")

    refute VM.await_reset(vm, 15_000), "device rebooted despite the kill-switch"
  end

  @tag vm_opts: [data_disk: %{size: "64M"}]
  test "a fault that recovers before its window does not reboot", %{vm: vm} do
    mount_recordings(vm)
    :ok = VM.call(vm, Application, :put_env, [:nvr_support, :storage_debounce_ms, 5_000])

    assert VM.call(vm, NvrSupport.Watchdog.Heart, :check, []) == :ok

    # Fail, then recover well before the 5s window qualifies.
    assert {_, 0} = VM.cmd(vm, "mount -o remount,ro #{@rec}")
    Process.sleep(2_000)
    assert {_, 0} = VM.cmd(vm, "mount -o remount,rw #{@rec}")

    refute VM.await_reset(vm, 15_000), "device rebooted even though the fault recovered in time"
  end

  @tag vm_opts: [data_disk: %{size: "64M"}]
  test "read-only storage does not reboot when no camera is configured", %{vm: vm} do
    assert {_, 0} =
             VM.cmd(vm, "mkdir -p #{@rec} && mkfs.ext4 -F -q /dev/vdb && mount /dev/vdb #{@rec}")

    :ok = VM.call(vm, Application, :put_env, [:nvr_support, :recordings_path, @rec])
    :ok = VM.call(vm, Application, :put_env, [:nvr_support, :storage_debounce_ms, 3_000])

    # No cameras configured -> an unwritable disk is not reboot-worthy.
    :ok = VM.call(vm, Application, :put_env, [:nvr_support, :devices, []])

    assert {_, 0} = VM.cmd(vm, "mount -o remount,ro #{@rec}")

    refute VM.await_reset(vm, 15_000),
           "device rebooted on read-only storage with no camera configured"
  end
end
