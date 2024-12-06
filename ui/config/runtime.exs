import Config

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/ex_nvr/ex_nvr.db
      """

  config :ex_nvr, ExNVR.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  config :ex_nvr,
    hls_directory: System.get_env("EXNVR_HLS_DIRECTORY", "./hls"),
    admin_username: System.get_env("EXNVR_ADMIN_USERNAME", "admin@localhost"),
    admin_password: System.get_env("EXNVR_ADMIN_PASSWORD", "P@ssw0rd")

  ice_servers =
    case Jason.decode(System.get_env("EXNVR_ICE_SERVERS", "[]"), keys: :atoms) do
      {:ok, servers} -> servers
      {:error, _reason} -> []
    end

  config :ex_nvr, ice_servers: ice_servers

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  url = URI.parse(System.get_env("EXNVR_URL", "http://localhost:4000"))

  check_origin =
    case System.get_env("EXNVR_CHECK_ORIGIN", "true") do
      "true" -> true
      "false" -> false
      origins -> String.split(origins, ",")
    end

  config :ex_nvr, ExNVRWeb.Endpoint,
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("EXNVR_HTTP_PORT") || "4000")
    ],
    secret_key_base: secret_key_base,
    url: [scheme: url.scheme, host: url.host, port: url.port],
    check_origin: check_origin

  ## SSL Support
  enable_ssl = String.to_existing_atom(System.get_env("EXNVR_ENABLE_HTTPS", "false"))

  if enable_ssl do
    config :ex_nvr, ExNVRWeb.Endpoint,
      https: [
        ip: {0, 0, 0, 0, 0, 0, 0, 0},
        port: String.to_integer(System.get_env("EXNVR_HTTPS_PORT") || "443"),
        cipher_suite: :compatible,
        keyfile: System.get_env("EXNVR_SSL_KEY_PATH"),
        certfile: System.get_env("EXNVR_SSL_CERT_PATH")
      ]
  end

  config :ex_nvr, ExNVRWeb.Endpoint, server: true

  ## Logging configuration
  log_json? = System.get_env("EXNVR_JSON_LOGGER", "true") == "true"

  if log_json? do
    config :logger_json, :backend,
      metadata: :all,
      formatter: LoggerJSON.Formatters.BasicLogger,
      on_init: :disabled

    config :logger, level: :info, backends: [LoggerJSON]
  end

  config :ex_nvr,
    enable_reverse_proxy: System.get_env("ENABLE_REVERSE_PROXY", "false") == "true"

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :ex_nvr, ExNVR.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
