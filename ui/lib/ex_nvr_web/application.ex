defmodule ExNVRWeb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :logger.add_handler(:my_sentry_handler, Sentry.LoggerHandler, %{
      config: %{
        metadata: [:file, :line],
        rate_limiting: [max_events: 10, interval: _1_second = 1_000],
        capture_log_messages: false
      }
    })

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
        {ExNvr.RemovableStorage.Mounter, []},
        {DynamicSupervisor, [name: ExNVR.Hardware.Supervisor, strategy: :one_for_one]},
        {ExNVR.Hardware.SerialPortChecker, []},
        Task.child_spec(fn -> ExNVR.start() end)
      ] ++ remote_connector()

    opts = [strategy: :one_for_one, name: ExNVRWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ExNVRWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp remote_connector do
    options = Application.get_env(:ex_nvr, :remote_server, [])

    if uri = Keyword.get(options, :uri) do
      token = options[:token]
      uri = if token, do: "#{uri}?token=#{token}", else: uri

      [{ExNVR.RemoteConnection, [uri: uri, message_handler: options[:message_handler]]}]
    else
      []
    end
  end
end
