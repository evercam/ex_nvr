defmodule ExNVRWeb.HealthDashboardLive do
  @moduledoc """
  Renders the system health dashboard at `/health`.

  Reads from `ExNVR.SystemStatus` (initial fetch + PubSub subscription) and
  queries `Mobius.Exports.series/4` for sparkline history. Stateless visual
  components live in `ExNVRWeb.Components.Health`; the template is the
  co-located `health_dashboard_live.html.heex`.
  """

  use ExNVRWeb, :live_view

  import ExNVRWeb.Components.Health

  require Logger

  alias ExNVR.SystemStatus

  # SystemStatus broadcasts on PubSub every 15s; this poll only exists to
  # refresh the device list (computed on-the-fly by SystemStatus.get_all/0)
  # and as a failover heartbeat if broadcasts ever go missing.
  @poll_interval to_timeout(minute: 1)
  @history_window {15, :minute}

  def mount(_params, _session, socket) do
    if connected?(socket) do
      SystemStatus.subscribe()
      Process.send_after(self(), :poll, @poll_interval)
    end

    {:ok,
     socket
     |> assign(
       status: safe_get_all(),
       last_update: DateTime.utc_now(),
       history_window: @history_window
     )
     |> assign_history()}
  end

  def handle_info({:system_status, data}, socket) do
    merged = Map.put(data, :devices, socket.assigns.status[:devices])

    {:noreply,
     socket
     |> assign(status: merged, last_update: DateTime.utc_now())
     |> assign_history()}
  end

  def handle_info(:poll, socket) do
    Process.send_after(self(), :poll, @poll_interval)

    {:noreply,
     socket
     |> assign(status: safe_get_all(), last_update: DateTime.utc_now())
     |> assign_history()}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  def terminate(_reason, _socket) do
    Phoenix.PubSub.unsubscribe(ExNVR.PubSub, SystemStatus.topic())
    :ok
  end

  defp safe_get_all do
    SystemStatus.get_all()
  rescue
    error ->
      Logger.warning("[HealthDashboard] SystemStatus.get_all/0 failed: #{inspect(error)}")
      %{}
  catch
    :exit, reason ->
      Logger.warning("[HealthDashboard] SystemStatus.get_all/0 exited: #{inspect(reason)}")
      %{}
  end

  defp assign_history(socket) do
    history = %{
      cpu_usage: series("ex_nvr.system.cpu.usage"),
      cpu_1m: series("ex_nvr.system.cpu.load_1m"),
      cpu_5m: series("ex_nvr.system.cpu.load_5m"),
      cpu_15m: series("ex_nvr.system.cpu.load_15m"),
      memory_used: series("ex_nvr.system.memory.used"),
      solar_voltage: series("ex_nvr.system.solar.voltage_mv"),
      solar_panel_power: series("ex_nvr.system.solar.panel_power_w"),
      solar_soc: series("ex_nvr.system.solar.soc")
    }

    pipeline_history = pipeline_history(socket.assigns.status[:devices])

    assign(socket, history: history, pipeline_history: pipeline_history)
  end

  # Builds %{device_id => %{stream_key => %{bitrate: [...], fps: [...], recv_bytes: [...]}}}
  # by pulling each per-stream Mobius series for the devices currently visible.
  defp pipeline_history(devices) when is_list(devices) do
    for device <- devices, into: %{} do
      {device[:id] || device.id, history_for_device(device)}
    end
  end

  defp pipeline_history(_), do: %{}

  defp history_for_device(device) do
    device_id = device[:id] || device.id
    streams = Map.keys(device[:stream_stats] || %{})

    for stream_key <- streams, into: %{} do
      {stream_key, history_for_stream(device_id, stream_key)}
    end
  end

  defp history_for_stream(device_id, stream_key) do
    tags = %{device_id: device_id, stream: stream_tag(stream_key)}

    %{
      bitrate: series("ex_nvr.device.stream.bitrate", tags),
      fps: series("ex_nvr.device.stream.fps", tags),
      recv_bytes: series("ex_nvr.device.stream.recv_bytes", tags)
    }
  end

  defp series(metric_name, tags \\ %{}) do
    Mobius.Exports.series(metric_name, :last_value, tags, last: @history_window)
  rescue
    error ->
      Logger.warning("[HealthDashboard] Mobius series #{metric_name} failed: #{inspect(error)}")

      []
  catch
    :exit, reason ->
      Logger.warning("[HealthDashboard] Mobius series #{metric_name} exited: #{inspect(reason)}")

      []
  end
end
