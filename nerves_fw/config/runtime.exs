import Config

defmodule ConfigParser do
  def parse_integrated_turn_ip(ip) do
    case :inet.parse_address(to_charlist(ip)) do
      {:ok, parsed_ip} ->
        parsed_ip

      _error ->
        raise """
        Bad EXTERNAL IP format. Expected IPv4, got: #{inspect(ip)}
        """
    end
  end

  def parse_integrated_turn_port_range(range) do
    with [str1, str2] <- String.split(range, "-"),
         from when from in 0..65_535 <- String.to_integer(str1),
         to when to in from..65_535 and from <= to <- String.to_integer(str2) do
      {from, to}
    else
      _else ->
        raise("""
        Bad INTEGRATED_TURN_PORT_RANGE environment variable value. Expected "from-to", where `from` and `to` \
        are numbers between 0 and 65535 and `from` is not bigger than `to`, got: \
        #{inspect(range)}
        """)
    end
  end

  def parse_port_number(nil, _var_name), do: nil

  def parse_port_number(port, var_name) do
    with {port, _sufix} when port in 1..65535 <- Integer.parse(port) do
      port
    else
      _var ->
        raise(
          "Bad #{var_name} environment variable value. Expected valid port number, got: #{inspect(port)}"
        )
    end
  end
end

if config_env() == :prod do
  config :ex_nvr, ExNVR.Repo,
    database: System.get_env("DATABASE_PATH", "/data/ex_nvr/ex_nvr.db"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  config :ex_nvr,
    hls_directory: System.get_env("EXNVR_HLS_DIRECTORY", "/tmp/hls"),
    admin_username: System.get_env("EXNVR_ADMIN_USERNAME", "admin@localhost"),
    admin_password: System.get_env("EXNVR_ADMIN_PASSWORD", "P@ssw0rd")

  config :ex_nvr,
    integrated_turn_ip:
      System.get_env("EXTERNAL_IP", "127.0.0.1") |> ConfigParser.parse_integrated_turn_ip(),
    integrated_turn_domain: System.get_env("VIRTUAL_HOST", "localhost"),
    integrated_turn_port_range:
      System.get_env("INTEGRATED_TURN_PORT_RANGE", "30000-30100")
      |> ConfigParser.parse_integrated_turn_port_range(),
    integrated_turn_tcp_port:
      System.get_env("INTEGRATED_TURN_TCP_PORT")
      |> ConfigParser.parse_port_number("INTEGRATED_TURN_TCP_PORT"),
    integrated_turn_pkey: System.get_env("INTEGRATED_TURN_PKEY"),
    integrated_turn_cert: System.get_env("INTEGRATED_TURN_CERT")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    if secret = System.get_env("SECRET_KEY_BASE") do
      secret
    else
      :crypto.strong_rand_bytes(48) |> Base.encode64()
    end

  url = URI.parse(System.get_env("EXNVR_URL", "http://localhost:4000"))

  check_origin =
    case System.get_env("EXNVR_CHECK_ORIGIN", "//*.evercam.io") do
      "true" -> true
      "false" -> false
      origins -> String.split(origins, ",")
    end

  config :ex_nvr, ExNVRWeb.Endpoint,
    http: [
      ip: {0, 0, 0, 0},
      port: String.to_integer(System.get_env("EXNVR_HTTP_PORT") || "4000")
    ],
    secret_key_base: secret_key_base,
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
        ip: {0, 0, 0, 0},
        port: String.to_integer(System.get_env("EXNVR_HTTPS_PORT") || "443"),
        cipher_suite: :compatible,
        keyfile: System.get_env("EXNVR_SSL_KEY_PATH"),
        certfile: System.get_env("EXNVR_SSL_CERT_PATH")
      ]
  end
end
