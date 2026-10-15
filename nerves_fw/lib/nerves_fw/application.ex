defmodule ExNVR.Nerves.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Nerves.Runtime

  @impl true
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: ExNVR.Nerves.Supervisor]

    children = [{Phoenix.PubSub, name: ExNVR.Nerves.PubSub}]

    children =
      if Application.get_env(:ex_nvr, :env) != :test do
        # Root folder of S3 footage exports (see ExNVR.Export.S3.kit_id/0). Read
        # on each export since the kit can be configured after boot.
        Application.put_env(:ex_nvr, :kit_id, fn ->
          ExNVR.Nerves.SystemSettings.get_settings().kit_serial
        end)

        children ++ [{ExNVR.Nerves.SystemSettings, []}]
      else
        children
      end

    children = children ++ children(target())

    ExNVR.Release.migrate()
    Supervisor.start_link(children, opts)
  end

  # List all child processes to be supervised
  def children(:host) do
    []
  end

  def children(:giraffe) do
    common_config() ++
      [
        {ExNVR.Nerves.Giraffe.Init, []},
        {ExNVR.Nerves.Giraffe.FanController, []},
        {ExNVR.Nerves.Monitoring.UPS, []}
      ]
  end

  def children(:recomputer_r22) do
    [{ExNVR.Nerves.RecomputerR22.Init, []}] ++ common_config()
  end

  def children(_target) do
    common_config() ++ [{ExNVR.Nerves.Monitoring.UPS, []}]
  end

  def target do
    Application.get_env(:ex_nvr_fw, :target)
  end

  def grafana_agent_config do
    [
      mac_address: VintageNet.get(["interface", "eth0", "mac_address"]),
      serial_number: Runtime.serial_number(),
      platform: Runtime.KV.get("a.nerves_fw_platform"),
      kit_id: Runtime.KV.get("nerves_evercam_id")
    ]
  end

  defp common_config do
    [
      {ExNVR.Nerves.SystemStatus, []},
      {ExNVR.Nerves.Netbird, []},
      {ExNVR.Nerves.DiskMounter, []},
      {ExNVR.Nerves.GrafanaAgent, grafana_agent_config()},
      {MuonTrap.Daemon, ["nginx", [], [stderr_to_stdout: true, log_output: :info]]},
      {ExNVR.Nerves.RemoteConfigurer, []},
      {ExNVR.Nerves.Monitoring.PowerSchedule, []},
      {ExNVR.Nerves.Monitoring.AutoReboot, []},
      {ExNVR.Nerves.Monitoring.Victron, []},
      {ExNVR.Nerves.RUT.Auth, []}
    ]
  end
end
