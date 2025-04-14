import Config

mix_target = Nerves.Runtime.mix_target()
{:ok, hostname} = :inet.gethostname()

url = URI.parse(System.get_env("EXNVR_URL", "http://localhost:4000"))

## SSL Support
enable_ssl = String.to_existing_atom(System.get_env("EXNVR_ENABLE_HTTPS", "false"))

# Start with Livebook defaults
Livebook.config_runtime()

# Store notebooks in a writable location on the device
notebook_path =
  if mix_target == :host do
    Path.expand("priv") <> "/"
  else
    "/data/livebook/"
  end

config :livebook,
  home: notebook_path,
  file_systems: [Livebook.FileSystem.Local.new(default_path: notebook_path)]

# Use the embedded runtime to run notebooks in the same VM
config :livebook,
  default_runtime: Livebook.Runtime.Embedded.new(),
  default_app_runtime: Livebook.Runtime.Embedded.new()

# # Configure plugs
# config :livebook,
#   plugs: [{NervesLivebook.RedirectNervesLocal, []}]

# Set the Erlang distribution cookie
config :livebook,
  node: :"livebook@#{url.host}",
  cookie: :ex_nvr_cookie

# Endpoint configuration
livebook_port = String.to_integer(System.get_env("EXNVR_LB_HTTP_PORT") || "9100")

config :livebook, LivebookWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: url.host, path: "/"],
  pubsub_server: Livebook.PubSub,
  live_view: [signing_salt: "livebook"],
  drainer: [shutdown: 1000],
  render_errors: [formats: [html: LivebookWeb.ErrorHTML], layout: false],
  http: [
    port: livebook_port,
    http_1_options: [max_header_length: 32768]
  ],
  code_reloader: false,
  server: true

config :livebook, :iframe_port, String.to_integer(System.get_env("EXNVR_LB_IFRAME_PORT") || "9102")
