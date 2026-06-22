# This file is responsible for configuring your application and its
# dependencies.
#
# This configuration file is loaded before any dependency and is restricted to
# this project.
import Config

config :logger, :console, level: :info

config :ex_nvr, ExNVR.Repo,
  database: Path.expand("../../ui/ex_nvr_dev.db", Path.dirname(__ENV__.file)),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :ex_nvr,
  hls_directory: Path.expand("../../ui/data/hls", Path.dirname(__ENV__.file)),
  run_pipelines: true

# Health checks for Evercam firmware: the shared baseline (cameras, CPU,
# memory) plus netbird and battery_monitor presence, both populated by
# nerves_fw/lib/nerves_fw/system_status.ex via SystemStatus.set/3.
config :ex_nvr, :health_checks, [
  %{
    name: :cameras,
    label: "Cameras recording",
    kind: :devices_recording
  },
  %{
    name: :cpu_usage,
    label: "CPU usage under 90% for 10 min",
    kind: :mobius_range,
    metric: "ex_nvr.system.cpu.usage",
    range: 0..90,
    window: {10, :minute}
  },
  %{
    name: :memory,
    label: "Memory under 90% for 10 min",
    kind: :mobius_range,
    metric: "ex_nvr.system.memory.used_pct",
    range: 0..90,
    window: {10, :minute}
  },
  %{
    name: :netbird,
    label: "Netbird connected",
    kind: :state_field,
    field: :netbird,
    path: ["daemonStatus"],
    expected: "Connected"
  },
  %{
    name: :battery_monitor,
    label: "Battery monitor reachable",
    kind: :state_field_present,
    field: :battery_monitor
  }
]

# Watchdog (nvr_support): drive Erlang's heart callback from Alarmist alarms so
# the device reboots when it stops doing its job. Windows are read at runtime, so
# they can also be overridden in runtime.exs or live (e.g. short for VM tests).
config :nvr_support,
  enabled: true,
  poll_interval_ms: :timer.seconds(30),
  storage_debounce_ms: :timer.minutes(15),
  internal_debounce_ms: :timer.minutes(5),
  recording_debounce_ms: :timer.minutes(30),
  recordings_path: "/data"

# Severity metadata for logging/filtering only (does not affect reboot logic).
config :alarmist, alarm_levels: %{NvrSupport.Watchdog.HealthCheck => :critical}

# Enable the Nerves integration with Mix
Application.start(:nerves_bootstrap)

config :ex_nvr_fw, target: Mix.target()

# Customize non-Elixir parts of the firmware. See
# https://hexdocs.pm/nerves/advanced-configuration.html for details.

config :nerves, :firmware,
  provisioning: :nerves_hub_link,
  rootfs_overlay: "rootfs_overlay",
  # -no-compression should imply ["-noI", "-noId", "-noD", "-noF", "-noX"]
  mksquashfs_flags: ["-noI", "-noId", "-noD", "-noF", "-noX", "-quiet"]

# Set the SOURCE_DATE_EPOCH date for reproducible builds.
# See https://reproducible-builds.org/docs/source-date-epoch/ for more information

config :nerves, source_date_epoch: "1729094794"

config :ex_nvr, env: :prod, nerves_routes: true

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :ex_nvr,
  namespace: ExNVR,
  ecto_repos: [ExNVR.Repo]

config :ex_nvr, ExNVR.Mailer, adapter: Swoosh.Adapters.Local

config :os_mon,
  disk_space_check_interval: {:second, 30},
  disk_almost_full_threshold: 0.9

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :bundlex, disable_precompiled_os_deps: true

config :membrane_core, enable_metrics: false

config :nerves_hub_link, connect: false

config :exqlite, force_build: true

if Mix.target() == :host do
  import_config "host.exs"
else
  import_config "target.exs"
end
