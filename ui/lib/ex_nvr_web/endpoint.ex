defmodule ExNVRWeb.Endpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :ex_nvr

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_ex_nvr_web_key",
    signing_salt: "bK9wcwJo",
    same_site: "Lax"
  ]

  socket "/socket", ExNVRWeb.UserSocket,
    websocket: [check_origin: false],
    longpoll: [check_origin: false]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:peer_data, :uri, :user_agent, session: @session_options]]

  origins =
    case System.get_env("EXNVR_CORS_ALLOWED_ORIGINS") do
      nil -> "*"
      origins -> String.split(origins, ~r/\s+/)
    end

  plug Corsica,
    max_age: 600,
    origins: origins,
    allow_credentials: true,
    allow_methods: :all,
    allow_headers: ~w(content-type authorization),
    expose_headers: ~w(x-request-id x-start-date x-timestamp)

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :ex_nvr,
    gzip: true,
    only: ExNVRWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :ex_nvr
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug PromEx.Plug, prom_ex_module: ExNVRWeb.PromEx
  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    body_reader: {ExNVR.Plug.CacheBodyReader, :read_body, []},
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Sentry.PlugContext

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug ExNVRWeb.Router

  def local_ip do
    with {:ok, ifs} <- :inet.getifaddrs(),
         {_, opts} <- List.keyfind(ifs, ~c"eth0", 0),
         addrs <- Keyword.get_values(opts, :addr),
         ipv4 <- Enum.find(addrs, &match?({_, _, _, _}, &1)) do
      ipv4
      |> :inet_parse.ntoa()
      |> to_string()
    else
      _ -> "127.0.0.1"
    end
  end

  def local_url do
    url = Application.get_env(:ex_nvr, __MODULE__, []) |> Keyword.get(:url, [])
    scheme = Keyword.get(url, :scheme, "http")
    port = Keyword.get(url, :port, 4000)

    "#{scheme}://#{local_ip()}:#{port}"
  end
end
