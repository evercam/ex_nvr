defmodule ExNVR.Nerves.SystemStatus do
  @moduledoc """
  Can nerves specific system status information and
  merge them with `ExNVR.SystemStatus`.
  """
  alias Mix.Tasks.Phx.Gen

  use GenServer

  def start_link(_options) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_options) do
    Process.send_after(self(), :collect_system_metrics, 0)
    {:ok, nil}
  end

  @impl true
  def handle_info(:collect_system_metrics, state) do
    hostname =
      case Nerves.Runtime.KV.get("nerves_evercam_id") do
        "" ->
          {:ok, hostname} = :inet.gethostname()
          List.to_string(hostname)

        evercam_id ->
          evercam_id
      end

    rut_data = ExNVR.Nerves.Monitoring.RUT.state()

    netbird_data =
      case ExNVR.Nerves.Netbird.status() do
        {:ok, data} -> data
        _error -> false
      end

    :ok = ExNVR.SystemStatus.set(:hostname, hostname)
    :ok = ExNVR.SystemStatus.set(:router, rut_data)
    :ok = ExNVR.SystemStatus.set(:netbird, netbird_data)
    :ok = ExNVR.SystemStatus.set(:nerves, true)
    :ok = ExNVR.SystemStatus.set(:device_model, Nerves.Runtime.KV.get_all("a.nerves_fw_platform"))

    Process.send_after(self(), :collect_system_metrics, to_timeout(second: 30))
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
