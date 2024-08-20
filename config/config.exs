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

config :ex_nvr_web,
  namespace: ExNVRWeb,
  ecto_repos: [ExNVR.Repo],
  generators: [context_app: :ex_nvr]

# Configures the endpoint
config :ex_nvr_web, ExNVRWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: ExNVRWeb.ErrorHTML, json: ExNVRWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ExNVR.PubSub,
  live_view: [signing_salt: "ASTBdstw"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js js/webrtc.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../apps/ex_nvr_web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.2.7",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../apps/ex_nvr_web/assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :soap, :globals, version: "1.2"

config :os_mon,
  disk_space_check_interval: {:second, 30},
  disk_almost_full_threshold: 0.9

config :bundlex, :disable_precompiled_os_deps, apps: [:ex_libsrtp]

# Additional mime types
config :mime, :types, %{
  "audio/m4a" => ["m4a"],
  "text/plain" => ["livemd"]
}

# Sets the default storage backend
config :livebook, :storage, Livebook.Storage.Ets

# Enable the embedded runtime which isn't available by default
config :livebook, :runtime_modules, [Livebook.Runtime.Embedded, Livebook.Runtime.Attached]

# Defaults for required configurations
config :livebook,
  agent_name: "default",
  allowed_uri_schemes: [],
  app_service_name: nil,
  app_service_url: nil,
  authentication: {:password, "password"},
  aws_credentials: false,
  epmdless: false,
  feature_flags: [],
  force_ssl_host: nil,
  plugs: [],
  rewrite_on: [],
  teams_auth?: false,
  teams_url: "https://teams.livebook.dev",
  update_instructions_url: nil,
  within_iframe: false

config :livebook, Livebook.Apps.Manager, retry_backoff_base_ms: 5_000

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
