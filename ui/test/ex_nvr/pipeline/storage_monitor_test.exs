defmodule ExNVR.Pipeline.StorageMonitorTest do
  use ExUnit.Case, async: true

  alias ExNVR.Model.Device
  alias ExNVR.Pipeline.StorageMonitor

  @moduletag :tmp_dir

  defp build_device(tmp_dir, recording_mode) do
    device = %Device{
      id: "test-#{System.unique_integer([:positive])}",
      timezone: "UTC",
      storage_config: %Device.StorageConfig{
        recording_mode: recording_mode,
        address: if(recording_mode != :none, do: tmp_dir),
        schedule: nil
      }
    }

    if recording_mode != :none do
      File.mkdir_p!(Device.base_dir(device))
    end

    device
  end

  describe "recording_mode :none" do
    test "immediately sends record? false and does not continue", %{tmp_dir: tmp_dir} do
      device = build_device(tmp_dir, :none)

      {:ok, pid} = StorageMonitor.start_link(device: device, pipeline_pid: self())

      assert_receive {:storage_monitor, :record?, false}
      refute_receive {:storage_monitor, :record?, true}, 100

      GenServer.stop(pid)
    end
  end

  describe "recording_mode :always" do
    test "sends record? true when directory is writable", %{tmp_dir: tmp_dir} do
      device = build_device(tmp_dir, :always)

      {:ok, pid} = StorageMonitor.start_link(device: device, pipeline_pid: self())

      assert_receive {:storage_monitor, :record?, true}

      GenServer.stop(pid)
    end

    test "pause and resume work", %{tmp_dir: tmp_dir} do
      device = build_device(tmp_dir, :always)

      {:ok, pid} = StorageMonitor.start_link(device: device, pipeline_pid: self())

      assert_receive {:storage_monitor, :record?, true}

      :ok = StorageMonitor.pause(pid)
      assert_receive {:storage_monitor, :record?, false}

      :ok = StorageMonitor.resume(pid)
      assert_receive {:storage_monitor, :record?, true}

      GenServer.stop(pid)
    end
  end
end
