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

config :ex_nvr,
  integrated_turn_ip: {127, 0, 0, 1},
  integrated_turn_domain: "localhost",
  integrated_turn_port_range: {30_000, 30_100},
  integrated_turn_tcp_port: 20_000,
  integrated_turn_pkey: nil,
  integrated_turn_cert: nil

# Enable the Nerves integration with Mix
Application.start(:nerves_bootstrap)

config :ex_nvr_fw, target: Mix.target()

# Customize non-Elixir parts of the firmware. See
# https://hexdocs.pm/nerves/advanced-configuration.html for details.

config :nerves, :firmware,
  provisioning: :nerves_hub_link,
  rootfs_overlay: "rootfs_overlay"

# Set the SOURCE_DATE_EPOCH date for reproducible builds.
# See https://reproducible-builds.org/docs/source-date-epoch/ for more information

config :nerves, source_date_epoch: "1729094794"

config :ex_nvr, env: :prod

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :ex_nvr,
  namespace: ExNVR,
  ecto_repos: [ExNVR.Repo]

config :ex_nvr, ExNVR.Mailer, adapter: Swoosh.Adapters.Local

config :soap, :globals, version: "1.2"

config :os_mon,
  disk_space_check_interval: {:second, 30},
  disk_almost_full_threshold: 0.9

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :bundlex, :disable_precompiled_os_deps,
  apps: [
    :ex_libsrtp,
    :membrane_h264_ffmpeg_plugin,
    :membrane_h265_ffmpeg_plugin,
    :membrane_ffmpeg_swscale_plugin,
    :ex_nvr
  ]

config :membrane_core, enable_metrics: false

config :tzdata, data_dir: "/data/elixir_tzdata"

config :nerves_hub_link, connect: false

if Mix.target() == :host do
  import_config "host.exs"
else
  import_config "target.exs"
end
