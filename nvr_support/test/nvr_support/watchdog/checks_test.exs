defmodule NvrSupport.Watchdog.ChecksTest do
  use ExUnit.Case, async: true

  alias NvrSupport.Watchdog.Checks

  describe "recording_stalled?/1" do
    test "false when no cameras are configured" do
      refute Checks.recording_stalled?([])
    end

    test "false when at least one camera is recording" do
      refute Checks.recording_stalled?([%{state: :recording}, %{state: :stopped}])
    end

    test "true when cameras exist but none are recording" do
      assert Checks.recording_stalled?([%{state: :stopped}, %{state: :failed}])
    end
  end

  describe "recording_ok?/1" do
    test "ok with an injected recording device" do
      assert Checks.recording_ok?(devices: [%{state: :recording}])
    end

    test "not ok when every device is stalled" do
      refute Checks.recording_ok?(devices: [%{state: :stopped}])
    end

    test "ok when no devices are configured" do
      assert Checks.recording_ok?(devices: [])
    end
  end

  describe "storage_writable?/1" do
    test "true for a writable directory" do
      assert Checks.storage_writable?(System.tmp_dir!())
    end

    test "false for a missing path" do
      refute Checks.storage_writable?("/no/such/path-#{System.unique_integer([:positive])}")
    end

    test "false for a read-only directory (e.g. a partition remounted ro)" do
      dir = Path.join(System.tmp_dir!(), "nvr_ro_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      File.chmod!(dir, 0o500)
      on_exit(fn ->
        File.chmod(dir, 0o700)
        File.rm_rf(dir)
      end)

      refute Checks.storage_writable?(dir)
    end
  end

  describe "storage_ok?/2 (gated on configured cameras)" do
    @missing "/no/such/path-gate"

    test "ok when the path is unwritable but no cameras are configured" do
      assert Checks.storage_ok?(@missing, devices: [])
    end

    test "not ok when the path is unwritable and a camera is configured" do
      refute Checks.storage_ok?(@missing, devices: [%{state: :recording}])
    end

    test "ok when a camera is configured and the path is writable" do
      assert Checks.storage_ok?(System.tmp_dir!(), devices: [%{state: :recording}])
    end
  end

  describe "devices_present?/1" do
    test "false when no cameras are configured" do
      refute Checks.devices_present?(devices: [])
    end

    test "true when at least one camera is configured" do
      assert Checks.devices_present?(devices: [%{state: :failed}])
    end
  end

  describe "internal_responsive?/1" do
    test "true when the probe succeeds" do
      assert Checks.internal_responsive?(probe: fn -> true end)
    end

    test "false when the probe raises" do
      refute Checks.internal_responsive?(probe: fn -> raise "boom" end)
    end

    test "false when the probe exits (e.g. a call timeout)" do
      refute Checks.internal_responsive?(probe: fn -> exit(:timeout) end)
    end
  end
end
