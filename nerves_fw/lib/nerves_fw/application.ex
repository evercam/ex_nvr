defmodule ExNVR.Nerves.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Nerves.Runtime

  @impl true
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: ExNVR.Nerves.Supervisor]

    children = [] ++ children(target())

    ExNVR.Release.migrate()

    Supervisor.start_link(children, opts)
  end

  # List all child processes to be supervised
  def children(:host) do
    []
  end

  def children(_target) do
    [
      {ExNVR.Nerves.Netbird, []},
      {ExNVR.Nerves.DiskMounter, []},
      {ExNVR.Nerves.GrafanaAgent, grafana_agent_config()},
      {ExNVR.Nerves.RemoteConfigurer, Application.get_env(:ex_nvr_fw, :remote_configurer)},
      {ExNVR.Nerves.Monitoring.RUT, rut_config()}
    ]
  end

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

  defp rut_config() do
    registry = ExNVR.SystemStatus.Supervisor.registry_name()

    ip =
      VintageNet.get(["interface", "eth0", "addresses"])
      |> Enum.find(%{address: {192, 168, 1, 1}}, &(&1.family == :inet))
      |> Map.get(:address)
      |> put_elem(3, 1)

    [registry: registry, ip: ip]
  end
end
