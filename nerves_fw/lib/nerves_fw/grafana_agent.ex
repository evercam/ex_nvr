defmodule ExNVR.Nerves.GrafanaAgent do
  @moduledoc """
  Start grafana agent as a port.
  """

  use Supervisor

  alias __MODULE__.ConfigRenderer

  @default_config [
    config_dir: "/data/grafana_agent",
    wal_directory: "/data/grafana_agent"
  ]

  def start_link(config) do
    Supervisor.start_link(__MODULE__, config, name: __MODULE__)
  end

  def reconfigure(new_config) do
    config = Keyword.merge(@default_config, new_config)
    config_dir = config[:config_dir]
    ConfigRenderer.generate_config_file(Map.new(config), config_dir)
    # This should be restarted by the supervisor
    Supervisor.stop(__MODULE__)
  end

  @impl true
  def init(config) do
    config = Keyword.merge(@default_config, config)
    config_dir = config[:config_dir]
    config_file = Path.join(config_dir, "agent.yml")

    unless File.exists?(config_dir) do
      File.mkdir!(config_dir)
    end

    unless File.exists?(config_file) do
      ConfigRenderer.generate_config_file(Map.new(config), config_dir)
    end

    children = [
      {MuonTrap.Daemon,
       [
         "grafana-agent",
         ["-config.file", config_file],
         [log_output: :info, stderr_to_stdout: true]
       ]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
