defmodule ExNVR.Nerves.Netbird do
  @moduledoc false

  use Supervisor

  require Logger

  alias __MODULE__.Client

  @default_config [
    config_file: "/data/netbird/config.json",
    daemon_addr: "unix:///data/netbird/netbird.sock",
    log_level: "info",
    log_file: "console"
  ]

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def up(management_url, setup_key, host \\ nil) do
    Client.up(management_url, setup_key, host)
  end

  defdelegate up, to: Client

  defdelegate status, to: Client

  defdelegate down, to: Client

  @impl true
  def init(opts) do
    opts = Keyword.merge(@default_config, opts)
    config_dir = opts[:config_file] |> Path.dirname()

    unless File.exists?(config_dir) do
      File.mkdir!(config_dir)
    end

    logger_fn = fn log ->
      case String.split(log, " ", parts: 3) do
        [_date_time, level, message] -> Logger.log(map_log_level(level), ["netbird: ", message])
        _other -> Logger.log(:info, log)
      end
    end

    children = [
      {MuonTrap.Daemon,
       ["netbird", netbird_args(opts), [logger_fun: logger_fn, stderr_to_stdout: true]]},
      {__MODULE__.Client, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp netbird_args(opts) do
    [
      "service",
      "run",
      "-c",
      opts[:config_file],
      "--daemon-addr",
      opts[:daemon_addr],
      "-l",
      opts[:log_level],
      "--log-file",
      opts[:log_file]
    ]
  end

  defp map_log_level("ERRO"), do: :error
  defp map_log_level("WARN"), do: :warning
  defp map_log_level(_other), do: :info
end
