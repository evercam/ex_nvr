defmodule ExNVRWeb.UserSocket do
  use Phoenix.Socket

  channel("device:*", ExNVRWeb.DeviceRoomChannel)

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, assign(socket, id: UUID.uuid4())}
  end

  @impl true
  def id(socket), do: socket.assigns[:id]
end
