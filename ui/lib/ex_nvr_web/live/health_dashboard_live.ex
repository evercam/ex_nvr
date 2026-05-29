defmodule ExNVRWeb.HealthDashboardLive do
  @moduledoc """
  Renders the system health dashboard.

  Mounted at two routes:

    * `/health` (`:index`) — admin-only entry point inside the regular app
      shell.
    * `/installer` (`:installer`) — public entry point gated by
      `ExNVR.InstallerMode.enabled?/0`; no app shell, redirects to the
      sign-in page when installer mode is off.

  Both routes render the same panels — system info, storage, network,
  per-camera stats with sparklines, and live JPEG snapshots refreshed
  every few seconds — only the wrapping chrome changes.

  Reads from `ExNVR.SystemStatus` (initial fetch + PubSub subscription) and
  queries `Mobius.Exports.series/4` for sparkline history. Stateless visual
  components live in `ExNVRWeb.Components.Health`; the template is the
  co-located `health_dashboard_live.html.heex`.
  """

  use ExNVRWeb, :live_view

  import ExNVRWeb.Components.Health

  require Logger

  alias ExNVR.{Devices, InstallerMode, SystemStatus}
  alias ExNVR.Model.Device

  # SystemStatus broadcasts on PubSub every 15s; this poll only exists to
  # refresh the device list (computed on-the-fly by SystemStatus.get_all/0)
  # and as a failover heartbeat if broadcasts ever go missing.
  @poll_interval to_timeout(minute: 1)
  @snapshot_interval to_timeout(second: 5)
  @history_window {15, :minute}

  def mount(_params, _session, socket) do
    installer? = socket.assigns.live_action == :installer

    if installer? and not InstallerMode.enabled?() do
      {:ok,
       socket
       |> put_flash(:error, "Installer mode is not enabled on this device.")
       |> push_navigate(to: ~p"/users/login"), layout: false}
    else
      mount_dashboard(socket, installer?)
    end
  end

  defp mount_dashboard(socket, installer?) do
    if connected?(socket) do
      SystemStatus.subscribe()
      Process.send_after(self(), :poll, @poll_interval)
      send(self(), :refresh_snapshots)
    end

    socket =
      socket
      |> assign(
        status: safe_get_all(),
        last_update: DateTime.utc_now(),
        last_snapshot_at: nil,
        snapshots: %{},
        history_window: @history_window,
        installer?: installer?
      )
      |> assign_history()

    if installer? do
      {:ok, socket, layout: false}
    else
      {:ok, socket}
    end
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

  def handle_info(:refresh_snapshots, socket) do
    Process.send_after(self(), :refresh_snapshots, @snapshot_interval)

    devices = Devices.ip_cameras()
    snapshots = Map.merge(socket.assigns.snapshots, fetch_snapshots(devices))

    {:noreply,
     assign(socket,
       snapshots: snapshots,
       last_snapshot_at: DateTime.utc_now()
     )}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  def terminate(_reason, _socket) do
    Phoenix.PubSub.unsubscribe(ExNVR.PubSub, SystemStatus.topic())
    :ok
  end

  defp fetch_snapshots(devices) do
    devices
    |> Enum.filter(&snapshot_capable?/1)
    |> Task.async_stream(
      fn device ->
        case Devices.fetch_snapshot(device) do
          {:ok, binary} ->
            {device.id, "data:image/jpeg;base64,#{Base.encode64(binary)}"}

          {:error, _reason} ->
            {device.id, nil}
        end
      end,
      ordered: false,
      timeout: 4_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{}, fn
      {:ok, {device_id, data}}, acc -> Map.put(acc, device_id, data)
      _other, acc -> acc
    end)
  end

  defp snapshot_capable?(%Device{state: state, stream_config: %{snapshot_uri: uri}})
       when not is_nil(uri),
       do: state in [:recording, :streaming]

  defp snapshot_capable?(_), do: false

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
