defmodule ExNVRWeb.DeviceRoomChannel do
  @moduledoc false

  use ExNVRWeb, :channel

  require Logger

  alias ExNVR.Devices.Room

  @impl true
  def join("device:" <> device_id, _params, socket) do
    device = ExNVR.Devices.get!(device_id)
    peer_id = UUID.uuid4()
    room_pid = ExNVR.Pipelines.Supervisor.room_pid(device)

    Room.add_peer(room_pid, self(), peer_id)

    {:ok, assign(socket, room: room_pid, peer_id: peer_id)}
  end

  @impl true
  def handle_in("media_event", media_event, socket) do
    room = socket.assigns.room
    send(room, {:media_event, socket.assigns.peer_id, media_event})
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
