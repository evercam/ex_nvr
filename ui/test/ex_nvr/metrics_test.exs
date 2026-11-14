defmodule ExNVR.MetricsTest do
  use ExUnit.Case, async: true

  test "list/0 returns Telemetry.Metrics specs covering the expected names" do
    metrics = ExNVR.Metrics.list()

    refute Enum.empty?(metrics)
    Enum.each(metrics, fn metric -> assert is_struct(metric, Telemetry.Metrics.LastValue) end)

    names = MapSet.new(metrics, &Enum.join(&1.name, "."))

    for expected <- [
          "ex_nvr.system.cpu.usage",
          "ex_nvr.system.cpu.load_1m",
          "ex_nvr.system.memory.used",
          "ex_nvr.system.storage.used",
          "ex_nvr.system.solar.voltage_mv",
          "ex_nvr.device.stream.bitrate"
        ] do
      assert MapSet.member?(names, expected), "missing metric: #{expected}"
    end
  end
end
