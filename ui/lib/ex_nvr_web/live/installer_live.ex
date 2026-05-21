defmodule ExNVRWeb.InstallerLive do
  @moduledoc """
  Public installer dashboard at `/installer`, gated by
  `ExNVR.InstallerMode.enabled?/0`.

  Combines the read-only system health view with live camera snapshots
  refreshed every few seconds so an on-site installer can verify the
  device and tune camera placement without needing admin credentials.
  """

  use ExNVRWeb, :live_view

  import ExNVRWeb.Components.Health

  require Logger

  alias ExNVR.{Devices, InstallerMode, SystemStatus}
  alias ExNVR.Model.Device

  @snapshot_interval to_timeout(second: 5)
  @status_poll_interval to_timeout(second: 15)

  def mount(_params, _session, socket) do
    if InstallerMode.enabled?() do
      mount_enabled(socket)
    else
      {:ok,
       socket
       |> put_flash(:error, "Installer mode is not enabled on this device.")
       |> push_navigate(to: ~p"/users/login"), layout: false}
    end
  end

  defp mount_enabled(socket) do
    if connected?(socket) do
      SystemStatus.subscribe()
      send(self(), :refresh_snapshots)
      Process.send_after(self(), :poll_status, @status_poll_interval)
    end

    devices = Devices.ip_cameras()

    {:ok,
     socket
     |> assign(
       status: safe_get_all(),
       devices: devices,
       snapshots: %{},
       last_update: DateTime.utc_now(),
       last_snapshot_at: nil
     ), layout: false}
  end

  def handle_info({:system_status, data}, socket) do
    {:noreply, assign(socket, status: data, last_update: DateTime.utc_now())}
  end

  def handle_info(:poll_status, socket) do
    Process.send_after(self(), :poll_status, @status_poll_interval)
    {:noreply, assign(socket, status: safe_get_all(), last_update: DateTime.utc_now())}
  end

  def handle_info(:refresh_snapshots, socket) do
    Process.send_after(self(), :refresh_snapshots, @snapshot_interval)
    devices = Devices.ip_cameras()
    snapshots = Map.merge(socket.assigns.snapshots, fetch_snapshots(devices))

    {:noreply,
     assign(socket,
       devices: devices,
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

  defp snapshot_placeholder(%Device{stream_config: %{snapshot_uri: nil}}),
    do: "No snapshot URL configured"

  defp snapshot_placeholder(%Device{state: :stopped}), do: "Device stopped"
  defp snapshot_placeholder(%Device{state: :failed}), do: "Device failed"
  defp snapshot_placeholder(_), do: "Waiting for first frame…"

  defp safe_get_all do
    SystemStatus.get_all()
  rescue
    error ->
      Logger.warning("[Installer] SystemStatus.get_all/0 failed: #{inspect(error)}")
      %{}
  catch
    :exit, reason ->
      Logger.warning("[Installer] SystemStatus.get_all/0 exited: #{inspect(reason)}")
      %{}
  end
end
