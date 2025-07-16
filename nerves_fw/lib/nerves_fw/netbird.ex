defmodule ExNVR.Nerves.Netbird do
  @moduledoc false

  use Supervisor

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

  def up, do: Client.up()

  def status, do: Client.status()

  @impl true
  def init(opts) do
    opts = Keyword.merge(@default_config, opts)
    config_dir = opts[:config_file] |> Path.dirname()

    unless File.exists?(config_dir) do
      File.mkdir!(config_dir)
    end

    children = [
      {MuonTrap.Daemon,
       ["netbird", netbird_args(opts), [log_output: :info, stderr_to_stdout: true]]},
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
end
