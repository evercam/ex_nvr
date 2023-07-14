defmodule ExNVRWeb.DeviceRoomChannel do
  @moduledoc false

  use ExNVRWeb, :channel

  require Logger

  @impl true
  def join("device:" <> device_id, _params, socket) do
    device = ExNVR.Devices.get!(device_id)
    peer_id = UUID.uuid4()

    ExNVR.Pipelines.Main.add_webrtc_peer(device, peer_id, self())

    {:ok, assign(socket, device: device, peer_id: peer_id)}
  end

  @impl true
  def handle_in("media_event", media_event, socket) do
    %{device: device, peer_id: peer_id} = socket.assigns
    ExNVR.Pipelines.Main.add_webrtc_media_event(device, peer_id, media_event)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:media_event, media_event}, socket) do
    push(socket, "media_event", %{data: media_event})
    {:noreply, socket}
  end

  @impl true
  def handle_info(message, socket) do
    Logger.warn("""
    Received unexpected message
    #{inspect(message)}
    """)

    {:noreply, socket}
  end
end
