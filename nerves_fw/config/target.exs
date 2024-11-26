import Config

config :ex_nvr, env: :prod

config :ex_nvr, ExNVR.Repo,
  database: System.get_env("DATABASE_PATH", "/data/ex_nvr/ex_nvr.db"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

config :ex_nvr,
  hls_directory: System.get_env("EXNVR_HLS_DIRECTORY", "/tmp/hls"),
  admin_username: System.get_env("EXNVR_ADMIN_USERNAME", "admin@localhost"),
  admin_password: System.get_env("EXNVR_ADMIN_PASSWORD", "P@ssw0rd")

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

# Use Ringlogger as the logger backend and remove :console.
# See https://hexdocs.pm/ring_logger/readme.html for more information on
# configuring ring_logger.

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

# Configure the device for SSH IEx prompt access and firmware updates
#
# * See https://hexdocs.pm/nerves_ssh/readme.html for general SSH configuration
# * See https://hexdocs.pm/ssh_subsystem_fwup/readme.html for firmware updates

keys =
  [
    Path.join([System.user_home!(), ".ssh", "id_rsa.pub"]),
    Path.join([System.user_home!(), ".ssh", "id_ecdsa.pub"]),
    Path.join([System.user_home!(), ".ssh", "id_ed25519.pub"])
  ]
  |> Enum.filter(&File.exists?/1)

if keys == [],
  do:
    Mix.raise("""
    No SSH public keys found in ~/.ssh. An ssh authorized key is needed to
    log into the Nerves device and update firmware on it using ssh.
    See your project's config.exs for this error message.
    """)

config :nerves_ssh,
  authorized_keys:
    Enum.map(keys, &File.read!/1) ++
      [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDhPsLGOiChQYeH1sqRH7/yCj+Dd4f0tv+01aszpO1FubTWcCYNFQCZsG+0sidi5i0LO+Bt9gPZvz0tl3qZYKcj4y231pFNwGHkxTo02h22AJ/aIZ+fbCejztxecCaPPz5Q4OH4ehsSL1TgoIlqw/5X55dVX6Z32o2O6MAmKcGl7zsWjFI+tkm9rNtQKLazGinNiVhEMgu9Uh+vWt+IKsispziPeCPKrl65sgzF2J74rQvD37DalkGKUoPyQnK9Yg7Sl3KfJqmHFqz9fLyqHTcAm8aOhjDVGzv4lEh/gs6Mh8/ZqywsArvbehigD9utNAmsxiXSWugGqdiqsL05xxdHLCcHUFYR/dsO5Lt4o0Sp1w3jNHrgUPha6hUptHF+t9MrPx48qL4kzT8JRY0TUsL14BA1ElxA/Tso+uXqbv24OCp46AzpNqHlJUmZkXIaLK9bwwukYaaFZ0lG7mf05GFosGBXQ7PP7lVtYbbAtkjCV8Lx5SskT7Ym1rklw7UGhts= imcha@DellTree",
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH+CB6jKOH2BnJ2l6jLmNV6GjL/AAlWF6/IPjshV7jaS deployment"
      ]

# Configure the network using vintage_net
#
# Update regulatory_domain to your 2-letter country code E.g., "US"
#
# See https://github.com/nerves-networking/vintage_net for more information
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
  host: "manage.nervescloud.com",
  remote_iex: true,
  shared_secret: [
    product_key: System.get_env("NERVES_HUB_PRODUCT_KEY", "fake_key"),
    product_secret: System.get_env("NERVES_HUB_PRODUCT_SECRET", "fake_secret")
  ],
  fwup_public_keys: [
    "iKuGXqQaMi4xwDRYobdGM0uO/BS4Kmpt0sFrkGGTLSE="
  ]

config :ex_nvr_fw, :remote_configurer,
  url: System.get_env("REMOTE_CONFIGURER_URL", "http://localhost:4000"),
  token: System.get_env("REMOTE_CONFIGURER_TOKEN"),
  api_version: System.get_env("REMOTE_CONFIGURER_VERSION")

# Import target specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
# Uncomment to use target specific configurations

# import_config "#{Mix.target()}.exs"
