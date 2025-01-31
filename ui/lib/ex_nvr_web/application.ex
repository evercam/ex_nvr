defmodule ExNVRWeb.Application do
  @moduledoc false

  use Application

  alias ExNVR.Hardware.SolarCharger.VictronMPPT

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
        Task.child_spec(fn -> ExNVR.start() end),
        ExNVRWeb.Telemetry,
        ExNVRWeb.Endpoint,
        ExNVRWeb.PromEx,
        {ExNVRWeb.HlsStreamingMonitor, []}
      ] ++ solar_charger() ++ remote_connector()

    opts = [strategy: :one_for_one, name: ExNVRWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ExNVRWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp solar_charger() do
    # VE.DIRECT to usb
    Circuits.UART.enumerate()
    |> Enum.find(fn {_port, details} ->
      details[:manufacturer] == "VictronEnergy BV" and details[:vendor_id] == 1027
    end)
    |> case do
      {port, _details} -> [{VictronMPPT, [port: port]}]
      nil -> []
    end
  end

  defp remote_connector() do
    options = Application.get_env(:ex_nvr, :remote_connection, [])

    if uri = Keyword.get(options, :uri) do
      token = options[:token]
      uri = if token, do: "#{uri}?token=#{token}", else: uri

      [{ExNVR.RemoteConnection, [uri: uri]}]
    else
      []
    end
  end
end
