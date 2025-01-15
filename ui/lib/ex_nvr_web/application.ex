defmodule ExNVRWeb.Application do
  @moduledoc false

  use Application

  @cert_file_path "priv/integrated_turn_cert.pem"

  @impl true
  def start(_type, _args) do
    children = [
      ExNVR.Repo,
      ExNVR.TokenPruner,
      {Phoenix.PubSub, name: ExNVR.PubSub},
      {Finch, name: ExNVR.Finch},
      {Task.Supervisor, name: ExNVR.TaskSupervisor},
      {ExNVR.SystemStatus.Supervisor, []},
      {DynamicSupervisor, [name: ExNVR.PipelineSupervisor, strategy: :one_for_one]},
      Task.child_spec(fn -> ExNVR.start() end),
      ExNVRWeb.Telemetry,
      ExNVRWeb.Endpoint,
      ExNVRWeb.PromEx,
      {ExNVRWeb.HlsStreamingMonitor, []}
    ]

    opts = [strategy: :one_for_one, name: ExNVRWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ExNVRWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  @impl true
  def stop(_state) do
    delete_cert_file()
    :ok
  end

  defp delete_cert_file(), do: File.rm(@cert_file_path)
end
