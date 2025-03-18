defmodule ExNVRWeb.Application do
  @moduledoc false

  use Application

  alias ExNVR.Hardware.Victron

  @impl true
  def start(_type, _args) do
    children =
      [
        ExNVR.Repo,
        ExNVR.TokenPruner,
        {Phoenix.PubSub, name: ExNVR.PubSub},
        {Finch, name: ExNVR.Finch},
        {Task.Supervisor, name: ExNVR.TaskSupervisor},
        {ExNVR.SystemStatus, []},
        {DynamicSupervisor, [name: ExNVR.PipelineSupervisor, strategy: :one_for_one]},
        ExNVRWeb.Telemetry,
        ExNVRWeb.Endpoint,
        ExNVRWeb.PromEx,
        {ExNVRWeb.HlsStreamingMonitor, []},
        {DynamicSupervisor, [name: ExNVR.HardwareMonitor, strategy: :one_for_one]},
        Task.child_spec(fn ->
          ExNVR.start()

          Circuits.UART.enumerate()
          |> Map.keys()
          |> Enum.filter(&(&1 not in ["ttyS0", "ttyS1", "ttyAMA0", "ttyAMA10"]))
          |> Enum.each(
            &DynamicSupervisor.start_child(ExNVR.HardwareMonitor, {Victron, [port: &1]})
          )
        end)
      ] ++ remote_connector()

    opts = [strategy: :one_for_one, name: ExNVRWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ExNVRWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp remote_connector() do
    options = Application.get_env(:ex_nvr, :remote_server, [])

    if uri = Keyword.get(options, :uri) do
      token = options[:token]
      uri = if token, do: "#{uri}?token=#{token}", else: uri

      [{ExNVR.RemoteConnection, [uri: uri]}]
    else
      []
    end
  end
end
