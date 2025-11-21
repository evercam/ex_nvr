defmodule ExNVR.Nerves.SystemStatus do
  @moduledoc """
  Can nerves specific system status information and
  merge them with `ExNVR.SystemStatus`.
  """

  use GenServer

  require Logger

  alias ExNVR.Nerves.Monitoring.UPS
  alias ExNVR.Nerves.{Netbird, RUT, SystemSettings}
  alias Nerves.Runtime

  @runs_summary_interval to_timeout(hour: 1)
  @run_gap_seconds 1800

  def start_link(_options) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_options) do
    Process.send_after(self(), :collect_system_metrics, to_timeout(second: 2))
    {:ok, ref} = :timer.send_interval(@runs_summary_interval, :runs_summary)
    {:ok, %{timer_ref: ref}}
  end

  @impl true
  def handle_info(:collect_system_metrics, state) do
    :ok = ExNVR.SystemStatus.set(:hostname, hostname())
    :ok = ExNVR.SystemStatus.set(:router, rut_data())
    :ok = ExNVR.SystemStatus.set(:netbird, netbird())
    :ok = ExNVR.SystemStatus.set(:nerves, true)
    :ok = ExNVR.SystemStatus.set(:device_model, Runtime.KV.get("a.nerves_fw_platform"))
    :ok = ExNVR.SystemStatus.set(:ups, ups_data())

    Process.send_after(self(), :collect_system_metrics, to_timeout(second: 30))
    {:noreply, state}
  end

  @impl true
  def handle_info(:runs_summary, state) do
    Logger.info("[SystemStatus] Collecting runs summary")

    Task.start(fn ->
      summary = ExNVR.Recordings.runs_summary(@run_gap_seconds)
      ExNVR.RemoteConnection.push_event("runs-summary", summary)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp hostname do
    case SystemSettings.get_settings().kit_serial do
      nil -> :inet.gethostname() |> elem(1) |> List.to_string()
      evercam_id -> evercam_id
    end
  end

  defp netbird do
    case Netbird.status() do
      {:ok, data} -> data
      _error -> false
    end
  end

  defp rut_data do
    case RUT.system_information() do
      {:ok, data} -> data
      _error -> nil
    end
  end

  defp ups_data do
    case Process.whereis(UPS) do
      pid when is_pid(pid) -> UPS.state(pid)
      _other -> nil
    end
  end
end
