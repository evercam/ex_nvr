defmodule ExNVRWeb.UserSocket do
  use Phoenix.Socket

  channel("device:*", ExNVRWeb.DeviceRoomChannel)

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Phoenix.Token.verify(socket, "user socket", token, max_age: 3_600 * 24) do
      {:ok, user_id} ->
        {:ok, assign(socket, user_id: user_id)}

      {:error, _reason} ->
        :error
    end
  end

  @impl true
  def id(socket), do: socket.assigns[:user_id]
end
