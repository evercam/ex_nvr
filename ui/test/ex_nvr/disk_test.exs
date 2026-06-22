defmodule ExNVR.DiskTest do
  @moduledoc false
  use ExUnit.Case, async: false
  use Mimic

  alias ExNVR.Disk

  # The smartctl probe runs in a process under ExNVR.TaskSupervisor, so the
  # System stubs have to be visible from other processes too.
  setup :set_mimic_global

  @smartctl_path "/usr/sbin/smartctl"

  describe "smartctl_get_disk_info/1" do
    setup do
      stub(System, :find_executable, fn "smartctl" -> @smartctl_path end)
      :ok
    end

    test "degrades to empty info when the probe task exits abnormally (issue #36)" do
      # The probe task crashes (here System.cmd itself raises), so Task.yield/2
      # returns {:exit, reason}. The caller must degrade to %{} rather than blow
      # up with a CaseClauseError.
      stub(System, :cmd, fn @smartctl_path, _args, _opts -> raise "smartctl blew up" end)

      assert Disk.smartctl_get_disk_info("/dev/sda") == %{}
    end

    test "degrades to empty info when smartctl output isn't valid JSON" do
      # smartctl exits 0 but prints non-JSON; JSON.decode/1 returns an error so
      # the probe yields %{} without the task crashing at all.
      stub(System, :cmd, fn @smartctl_path, _args, _opts -> {"not valid json", 0} end)

      assert Disk.smartctl_get_disk_info("/dev/sda") == %{}
    end
  end
end
