# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :ex_nvr, env: :dev

# Configure Mix tasks and generators
config :ex_nvr,
  namespace: ExNVR,
  ecto_repos: [ExNVR.Repo]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :ex_nvr, ExNVR.Mailer, adapter: Swoosh.Adapters.Local

config :ex_nvr,
  namespace: ExNVRWeb,
  ecto_repos: [ExNVR.Repo],
  generators: [context_app: :ex_nvr]

# Configures the endpoint
config :ex_nvr, ExNVRWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: ExNVRWeb.ErrorHTML, json: ExNVRWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ExNVR.PubSub,
  live_view: [signing_salt: "ASTBdstw"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :os_mon,
  disk_space_check_interval: {:second, 30},
  disk_almost_full_threshold: 0.9

config :bundlex, :disable_precompiled_os_deps, apps: [:ex_libsrtp]

config :exqlite, force_build: true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
