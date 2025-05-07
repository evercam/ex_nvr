import Config

Code.require_file("../mix/utils.exs", __DIR__)

# Configure your database
config :ex_nvr, ExNVR.Repo,
  database: Path.expand("../ex_nvr_dev.db", Path.dirname(__ENV__.file)),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :ex_nvr,
  hls_directory: Path.expand("../data/hls", Path.dirname(__ENV__.file)),
  run_pipelines: true

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with esbuild to bundle .js and .css sources.
config :ex_nvr, ExNVRWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "N3BcJ3uTqFM8etN2w9NAYYYjqaGQTGwLL1qM2vXt7yF5VqXnas30RBqci94ZLKvB",
  watchers: [
    npm: ["--silent", "run", "dev", cd: Path.expand("../assets", __DIR__)]
  ]

# Watch static and templates for browser reloading.
config :phoenix_live_reload, :dirs, ExNVR.Mix.Utils.watch_dirs()

config :ex_nvr, ExNVRWeb.Endpoint,
  live_reload: [
    patterns: ExNVR.Mix.Utils.watch_patterns()
  ]

# Enable dev routes for dashboard and mailbox
config :ex_nvr, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :console,
  level: :info,
  metadata: [:device_id, :user_id, :request_id],
  format: "$dateT$time [$level] $message\n"

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

config :live_vue,
  vite_host: "http://localhost:5173",
  ssr_module: LiveVue.SSR.ViteJS,
  ssr: false
