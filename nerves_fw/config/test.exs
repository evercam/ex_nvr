import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

config :ex_nvr, env: :test

config :ex_nvr, ExNVR.Repo,
  database: Path.expand("../ex_nvr_test.db", Path.dirname(__ENV__.file)),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

config :ex_nvr, ExNVRWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "v98YSVCUiOPDgBqTeAgebEm5zT1KY+FS4rtFe9BVzFzeiK9Gu8m7JxGgUCnIcPj/",
  server: false,
  code_reloader: false

config :logger, level: :warning

# In test we don't send emails.
config :ex_nvr, ExNVR.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :ex_nvr, ExNVRWeb.PromEx, disabled: true
