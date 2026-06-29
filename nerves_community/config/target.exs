import Config

config :ex_nvr, env: :prod

config :ex_nvr, ExNVR.Repo,
  database: System.get_env("DATABASE_PATH", "/data/ex_nvr/ex_nvr.db"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

config :ex_nvr,
  hls_directory: "/tmp/hls",
  admin_username: "admin@localhost",
  admin_password: "P@ssw0rd",
  download_dir: "/data/ex_nvr/downloads"

config :ex_nvr, ice_servers: System.get_env("EXNVR_ICE_SERVERS", "[]")

config :ex_nvr, ExNVRWeb.Endpoint,
  http: [
    ip: {0, 0, 0, 0, 0, 0, 0, 0},
    port: 4000
  ],
  secret_key_base: "l&vZd6mh2DS3%ES17EvnAh&OKnVvXg70Dh0pruTg96B%G29a@es$UROg8qI9be0G",
  url: [scheme: "http", host: "nvr.local", port: 4000],
  check_origin: false,
  server: true,
  render_errors: [
    formats: [html: ExNVRWeb.ErrorHTML, json: ExNVRWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ExNVR.PubSub,
  live_view: [signing_salt: "ASTBdstw"]

config :logger, backends: [RingLogger]

config :logger, RingLogger, level: :info

config :shoehorn, init: [:nerves_runtime, :nerves_pack]

config :nerves, :erlinit, update_clock: true

config :nerves_ssh,
  authorized_keys: [],
  user_passwords: [{"exnvr", "nerves"}]

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
  hosts: [:hostname, "nvr"],
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

config :tzdata, data_dir: "/data/elixir_tzdata"
