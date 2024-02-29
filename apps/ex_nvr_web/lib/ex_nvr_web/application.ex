defmodule ExNVRWeb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
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
end
