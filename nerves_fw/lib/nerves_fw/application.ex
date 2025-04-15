defmodule ExNVR.Nerves.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Nerves.Runtime

  @impl true
  def start(_type, _args) do
    initialize_data_directory()

    opts = [strategy: :one_for_one, name: ExNVR.Nerves.Supervisor]

    children = [] ++ children(target())

    ExNVR.Release.migrate()

    Supervisor.start_link(children, opts)
  end

  # List all child processes to be supervised
  def children(:host) do
    []
  end

  def children(:giraffe) do
    [{ExNVR.Nerves.Giraffe.Init, []}] ++ common_config()
  end

  def children(_target), do: common_config()

  def target() do
    Application.get_env(:ex_nvr_fw, :target)
  end

  def grafana_agent_config() do
    [
      mac_address: VintageNet.get(["interface", "eth0", "mac_address"]),
      serial_number: Runtime.serial_number(),
      platform: Runtime.KV.get("a.nerves_fw_platform"),
      kit_id: Runtime.KV.get("nerves_evercam_id")
    ]
  end

  defp initialize_data_directory() do
    destination_dir = "/data/livebook"
    source_dir = Application.app_dir(:ex_nvr_fw, "priv")

    # Best effort create everything
    _ = File.mkdir_p(destination_dir)
    Enum.each(["welcome.livemd", "samples"], &symlink(source_dir, destination_dir, &1))
  end

  defp symlink(source_dir, destination_dir, filename) do
    source = Path.join(source_dir, filename)
    dest = Path.join(destination_dir, filename)

    _ = File.rm(dest)
    _ = File.ln_s(source, dest)
  end

  defp common_config() do
    [
      {ExNVR.Nerves.Netbird, []},
      {ExNVR.Nerves.DiskMounter, []},
      {ExNVR.Nerves.GrafanaAgent, grafana_agent_config()},
      {MuonTrap.Daemon, ["nginx", [], [stderr_to_stdout: true, log_output: :info]]},
      {ExNVR.Nerves.RemoteConfigurer, Application.get_env(:ex_nvr_fw, :remote_configurer)},
      {ExNVR.Nerves.Monitoring.RUT, []},
      {ExNVR.Nerves.SystemStatus, []}
    ]
  end
end
