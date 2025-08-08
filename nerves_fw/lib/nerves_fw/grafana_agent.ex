defmodule ExNVR.Nerves.GrafanaAgent do
  @moduledoc """
  Start grafana agent as a port.
  """

  use GenServer

  require Logger

  alias __MODULE__.ConfigRenderer
  alias Nerves.Runtime

  @github_api_url "https://api.github.com/repos/grafana/agent/releases"

  @default_config [
    config_dir: "/data/grafana_agent",
    wal_directory: "/data/grafana_agent",
    prom_url: "http://localhost:9090",
    loki_url: "http://localhost:3000"
  ]

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def reconfigure(new_config) do
    GenServer.cast(__MODULE__, {:reconfigure, new_config})
  end

  @impl true
  def init(config) do
    config = Keyword.merge(@default_config, config)
    config_dir = config[:config_dir]
    config_file = Path.join(config_dir, "agent.yml")

    state = %{config_dir: config_dir, pid: nil}

    if not File.exists?(config_dir) do
      File.mkdir!(config_dir)
    end

    if not File.exists?(config_file) do
      ConfigRenderer.generate_config_file(Map.new(config), config_dir)
    end

    # Configure logging for devices that are
    # already configured. This will be deleted
    # in the next version (v0.23.0)
    configure_logging(state)

    case File.exists?(Path.join(config_dir, "grafana-agent")) do
      true ->
        {:ok, start_grafana_agent(state)}

      false ->
        Process.send_after(self(), :download, to_timeout(second: 5))
        {:ok, state}
    end
  end

  @impl true
  def handle_cast({:reconfigure, new_config}, state) do
    config = Keyword.merge(@default_config, new_config)
    ConfigRenderer.generate_config_file(Map.new(config), config[:config_dir])

    case state.pid do
      nil ->
        {:noreply, state}

      pid ->
        Process.exit(pid, :normal)
        {:noreply, start_grafana_agent(state)}
    end
  end

  @impl true
  def handle_info(:download, state) do
    Logger.info("Download grafana agent...")
    tmp_path = Path.join(System.tmp_dir!(), "grafana-agent.zip")

    %{status: 200} = Req.get!(grafana_agent_download_url(), into: File.stream!(tmp_path))

    Logger.info("Unzip grafana agent zip file...")
    {:ok, [grafana_agent]} = :zip.unzip(to_charlist(tmp_path), cwd: to_charlist(state.config_dir))
    File.rename!(List.to_string(grafana_agent), Path.join(state.config_dir, "grafana-agent"))

    File.rm!(tmp_path)

    {:noreply, start_grafana_agent(state)}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp grafana_agent_download_url do
    Req.get!(@github_api_url,
      headers: [{"content-type", "application/vnd.github+json"}],
      params: [per_page: 1]
    )
    |> Map.get(:body)
    |> List.first()
    |> Map.get("assets")
    # all our firmware are aarch64
    |> Enum.find(&String.ends_with?(&1["name"], "linux-arm64.zip"))
    |> Map.get("browser_download_url")
  end

  defp start_grafana_agent(%{config_dir: config_dir} = state) do
    {:ok, pid} =
      MuonTrap.Daemon.start_link(
        Path.join(config_dir, "grafana-agent"),
        ["-config.file", Path.join(config_dir, "agent.yml")],
        log_output: :info,
        stderr_to_stdout: true
      )

    %{state | pid: pid}
  end

  defp configure_logging(state) do
    config_file = Path.join(state.config_dir, "agent.yml")
    loki_config = loki_config()

    if loki_config != [] do
      ConfigRenderer.generate_log_config(loki_config, config_file)
    end
  end

  defp loki_config do
    kit_id = Runtime.KV.get("nerves_evercam_id")
    config = Application.get_env(:ex_nvr_fw, :loki, [])

    cond do
      kit_id == "" or is_nil(kit_id) ->
        []

      config == [] ->
        []

      true ->
        [
          loki_url: config[:url],
          loki_username: config[:username],
          loki_password: config[:password],
          kit_id: kit_id
        ]
    end
  end
end
