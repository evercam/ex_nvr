defmodule ExNVR.Metrics do
  @moduledoc """
  Telemetry metric definitions backed by Mobius for local time-series history.

  Metrics are populated by `ExNVR.SystemStatus` emitting telemetry events
  whenever it refreshes its data. Mobius stores recent samples in memory and
  can persist them; the health dashboard queries series via
  `Mobius.Exports.series/4`.
  """

  import Telemetry.Metrics

  @doc """
  Mobius metric definitions. Pass to `{Mobius, metrics: ExNVR.Metrics.list()}`.
  """
  @spec list() :: [Telemetry.Metrics.t()]
  def list do
    cpu_metrics() ++
      memory_metrics() ++ storage_metrics() ++ solar_metrics() ++ pipeline_metrics()
  end

  defp cpu_metrics do
    [
      last_value("ex_nvr.system.cpu.usage",
        event_name: [:ex_nvr, :system, :cpu],
        measurement: :usage,
        description: "Aggregate CPU busy percentage (0–100)"
      ),
      last_value("ex_nvr.system.cpu.load_1m",
        event_name: [:ex_nvr, :system, :cpu],
        measurement: :load_1m,
        description: "1-minute CPU load average"
      ),
      last_value("ex_nvr.system.cpu.load_5m",
        event_name: [:ex_nvr, :system, :cpu],
        measurement: :load_5m,
        description: "5-minute CPU load average"
      ),
      last_value("ex_nvr.system.cpu.load_15m",
        event_name: [:ex_nvr, :system, :cpu],
        measurement: :load_15m,
        description: "15-minute CPU load average"
      )
    ]
  end

  defp memory_metrics do
    [
      last_value("ex_nvr.system.memory.used",
        event_name: [:ex_nvr, :system, :memory],
        measurement: :used,
        unit: :byte,
        description: "Used system memory"
      ),
      last_value("ex_nvr.system.memory.total",
        event_name: [:ex_nvr, :system, :memory],
        measurement: :total,
        unit: :byte
      ),
      last_value("ex_nvr.system.memory.available",
        event_name: [:ex_nvr, :system, :memory],
        measurement: :available,
        unit: :byte
      )
    ]
  end

  defp storage_metrics do
    [
      last_value("ex_nvr.system.storage.used",
        event_name: [:ex_nvr, :system, :storage],
        measurement: :used,
        unit: :byte,
        tags: [:name]
      ),
      last_value("ex_nvr.system.storage.size",
        event_name: [:ex_nvr, :system, :storage],
        measurement: :size,
        unit: :byte,
        tags: [:name]
      )
    ]
  end

  defp pipeline_metrics do
    [
      last_value("ex_nvr.device.stream.bitrate",
        event_name: [:ex_nvr, :device, :stream, :stats],
        measurement: :avg_bitrate,
        tags: [:device_id, :stream],
        description: "Average stream bitrate in bits/s"
      ),
      last_value("ex_nvr.device.stream.fps",
        event_name: [:ex_nvr, :device, :stream, :stats],
        measurement: :avg_fps,
        tags: [:device_id, :stream]
      ),
      last_value("ex_nvr.device.stream.recv_bytes",
        event_name: [:ex_nvr, :device, :stream, :stats],
        measurement: :recv_bytes,
        unit: :byte,
        tags: [:device_id, :stream]
      )
    ]
  end

  defp solar_metrics do
    [
      last_value("ex_nvr.system.solar.voltage_mv",
        event_name: [:ex_nvr, :system, :solar],
        measurement: :voltage_mv
      ),
      last_value("ex_nvr.system.solar.current_ma",
        event_name: [:ex_nvr, :system, :solar],
        measurement: :current_ma
      ),
      last_value("ex_nvr.system.solar.panel_voltage_mv",
        event_name: [:ex_nvr, :system, :solar],
        measurement: :panel_voltage_mv
      ),
      last_value("ex_nvr.system.solar.panel_power_w",
        event_name: [:ex_nvr, :system, :solar],
        measurement: :panel_power_w
      ),
      last_value("ex_nvr.system.solar.soc",
        event_name: [:ex_nvr, :system, :solar],
        measurement: :soc
      )
    ]
  end
end
