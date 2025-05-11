import Config

# Add configuration that is only needed when running on the host here.

config :nerves_runtime,
  kv_backend:
    {Nerves.Runtime.KVBackend.InMemory,
     contents: %{
       # The KV store on Nerves systems is typically read from UBoot-env, but
       # this allows us to use a pre-populated InMemory store when running on
       # host for development and testing.
       #
       # https://hexdocs.pm/nerves_runtime/readme.html#using-nerves_runtime-in-tests
       # https://hexdocs.pm/nerves_runtime/readme.html#nerves-system-and-firmware-metadata

       "nerves_fw_active" => "a",
       "a.nerves_fw_architecture" => "generic",
       "a.nerves_fw_description" => "N/A",
       "a.nerves_fw_platform" => "host",
       "a.nerves_fw_version" => "0.0.0"
     }}

config :circuits_gpio, default_backend: {Circuits.GPIO.CDev, test: true}

config :ex_nvr, ExNVRWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  url: [host: "localhost"],
  render_errors: [
    formats: [html: ExNVRWeb.ErrorHTML, json: ExNVRWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ExNVR.PubSub,
  live_view: [signing_salt: "ASTBdstw"],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "N3BcJ3uTqFM8etN2w9NAYYYjqaGQTGwLL1qM2vXt7yF5VqXnas30RBqci94ZLKvB",
  watchers: [
    npm: ["--silent", "run", "dev", cd: Path.expand("../../ui/assets", __DIR__)]
  ]

config :live_vue,
  vite_host: "http://localhost:5173",
  ssr_module: LiveVue.SSR.ViteJS,
  ssr: false

if Mix.env() == :test do
  import_config "test.exs"
end
