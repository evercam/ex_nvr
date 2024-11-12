defmodule ExNVR.Nerves.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: ExNVR.Nerves.Supervisor]

    children = [] ++ children(target())

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
      {ExNVR.Nerves.GrafanaAgent, grafana_agent_config()}
    ]
  end

  def target() do
    Application.get_env(:ex_nvr_fw, :target)
  end

  def grafana_agent_config() do
    [
      mac_address: VintageNet.get(["interface", "eth0", "mac_address"]),
      serial_number:
        File.read!("/sys/firmware/devicetree/base/serial-number") |> String.slice(0..-2),
      platform: Nerves.Runtime.KV.get("a.nerves_fw_platform"),
      kit_id: Nerves.Runtime.KV.get("nerves_evercam_id")
    ]
  end
end
