import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

config :ex_nvr, env: :test

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ex_nvr, ExNVR.Repo,
  database: Path.expand("../ex_nvr_test.db", Path.dirname(__ENV__.file)),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

config :ex_nvr, run_pipelines: false

# integrated turn variables
config :ex_nvr,
  integrated_turn_ip: {127, 0, 0, 1},
  integrated_turn_domain: "localhost",
  integrated_turn_port_range: {30_000, 30_100},
  integrated_turn_tcp_port: 20_000,
  integrated_turn_pkey: nil,
  integrated_turn_cert: nil

config :ex_nvr, :rtsp_transport, ExNVR.RTSP.Transport.Fake

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ex_nvr_web, ExNVRWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "v98YSVCUiOPDgBqTeAgebEm5zT1KY+FS4rtFe9BVzFzeiK9Gu8m7JxGgUCnIcPj/",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# In test we don't send emails.
config :ex_nvr, ExNVR.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :ex_nvr_web, ExNVRWeb.PromEx, disabled: true
