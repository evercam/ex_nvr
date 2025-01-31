import Config

config :ex_nvr, env: :prod

config :ex_nvr, ExNVR.Repo,
  database: System.get_env("DATABASE_PATH", "/data/ex_nvr/ex_nvr.db"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

config :ex_nvr,
  hls_directory: System.get_env("EXNVR_HLS_DIRECTORY", "/tmp/hls"),
  admin_username: System.get_env("EXNVR_ADMIN_USERNAME", "admin@localhost"),
  admin_password: System.get_env("EXNVR_ADMIN_PASSWORD", "P@ssw0rd"),
  download_dir: System.get_env("EXNVR_DOWNLOAD_DIR", "/data/ex_nvr/downloads")

config :ex_nvr, enable_reverse_proxy: true

config :ex_nvr, ice_servers: System.get_env("EXNVR_ICE_SERVERS", "[]")

# Remote connection via websocket
config :ex_nvr,
  remote_server: [
    uri: System.get_env("EXNVR_REMOTE_SERVER_URI"),
    token: System.get_env("EXNVR_REMOTE_SERVER_TOKEN")
  ]

url = URI.parse(System.get_env("EXNVR_URL", "http://localhost:4000"))

check_origin =
  case System.get_env("EXNVR_CHECK_ORIGIN", "//*.evercam.io") do
    "true" -> true
    "false" -> false
    origins -> String.split(origins, ",")
  end

config :ex_nvr, ExNVRWeb.Endpoint,
  http: [
    ip: {0, 0, 0, 0, 0, 0, 0, 0},
    port: String.to_integer(System.get_env("EXNVR_HTTP_PORT") || "4000")
  ],
  secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
  url: [scheme: url.scheme, host: url.host, port: url.port],
  check_origin: check_origin,
  server: true,
  render_errors: [
    formats: [html: ExNVRWeb.ErrorHTML, json: ExNVRWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ExNVR.PubSub,
  live_view: [signing_salt: "ASTBdstw"]

## SSL Support
enable_ssl = String.to_existing_atom(System.get_env("EXNVR_ENABLE_HTTPS", "false"))

if enable_ssl do
  config :ex_nvr, ExNVRWeb.Endpoint,
    https: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("EXNVR_HTTPS_PORT") || "443"),
      cipher_suite: :compatible,
      keyfile: System.fetch_env!("EXNVR_SSL_KEY_PATH"),
      certfile: System.fetch_env!("EXNVR_SSL_CERT_PATH")
    ]
end

config :logger, backends: [RingLogger]

config :logger, RingLogger, level: :info

# Use shoehorn to start the main application. See the shoehorn
# library documentation for more control in ordering how OTP
# applications are started and handling failures.

config :shoehorn, init: [:nerves_runtime, :nerves_pack]

# Erlinit can be configured without a rootfs_overlay. See
# https://github.com/nerves-project/erlinit/ for more information on
# configuring erlinit.

# Advance the system clock on devices without real-time clocks.
config :nerves, :erlinit, update_clock: true

keys =
  [
    Path.join([System.user_home!(), ".ssh", "id_rsa.pub"]),
    Path.join([System.user_home!(), ".ssh", "id_ecdsa.pub"]),
    Path.join([System.user_home!(), ".ssh", "id_ed25519.pub"])
  ]
  |> Enum.filter(&File.exists?/1)
  |> Kernel.++([
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH+CB6jKOH2BnJ2l6jLmNV6GjL/AAlWF6/IPjshV7jaS deployment"
  ])

config :nerves_ssh, authorized_keys: keys

config :vintage_net,
  regulatory_domain: "00",
  config: [
    {"usb0", %{type: VintageNetDirect}},
    {"eth0",
     %{
       type: VintageNetEthernet,
       ipv4: %{method: :dhcp}
     }},
    {"wlan0", %{type: VintageNetWiFi}}
  ]

config :mdns_lite,
  # The `hosts` key specifies what hostnames mdns_lite advertises.  `:hostname`
  # advertises the device's hostname.local. For the official Nerves systems, this
  # is "nerves-<4 digit serial#>.local".  The `"nerves"` host causes mdns_lite
  # to advertise "nerves.local" for convenience. If more than one Nerves device
  # is on the network, it is recommended to delete "nerves" from the list
  # because otherwise any of the devices may respond to nerves.local leading to
  # unpredictable behavior.

  hosts: [:hostname, "nerves"],
  ttl: 120,

  # Advertise the following services over mDNS.
  services: [
    %{
      protocol: "ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "sftp-ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "epmd",
      transport: "tcp",
      port: 4369
    }
  ]

config :nerves_hub_link,
  connect: true,
  host: URI.parse(System.fetch_env!("NERVES_HUB_URI")).host,
  remote_iex: true,
  shared_secret: [
    product_key: System.get_env("NERVES_HUB_PRODUCT_KEY", "fake_key"),
    product_secret: System.get_env("NERVES_HUB_PRODUCT_SECRET", "fake_secret")
  ],
  fwup_public_keys: [
    "iKuGXqQaMi4xwDRYobdGM0uO/BS4Kmpt0sFrkGGTLSE=",
    "cu1VGLQcf81MODI7Pd/l1Zx8WtMslxM99IRGOZx/ezw="
  ],
  health: [
    metadata: %{
      "router_mac_address" => {ExNVR.Nerves.Health.Metadata, :router_mac_address, []},
      "router_serial_number" => {ExNVR.Nerves.Health.Metadata, :router_serial_number, []}
    }
  ]

config :ex_nvr_fw, :remote_configurer,
  url: System.get_env("REMOTE_CONFIGURER_URL", "http://localhost:4000"),
  token: System.get_env("REMOTE_CONFIGURER_TOKEN"),
  api_version: System.get_env("REMOTE_CONFIGURER_VERSION")

config :logger, :keen_loki_logger,
  level: :info,
  format: "$metadata level=$level $message",
  metadata: [:request_id, :file, :module, :function],
  max_buffer: 10,
  loki_host: "http://127.0.0.1:3100",
  # basic_auth_user: "lokiuser",
  # basic_auth_password: "lokipassword",
  # finch_protocols: [:http2],
  mint_conn_opts: []

# Import target specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
# Uncomment to use target specific configurations

# import_config "#{Mix.target()}.exs"
