defmodule ExNVRWeb.UserSocket do
  use Phoenix.Socket

  channel("device:*", ExNVRWeb.DeviceRoomChannel)

  alias ExNVR.Accounts

  @impl true
  def connect(params, socket, _connect_info) do
    with access_token <- params["access_token"] || "",
         {:ok, decodec_token} <- Base.decode64(access_token),
         user when not is_nil(user) <- Accounts.get_user_by_access_token(decodec_token) do
      {:ok, assign(socket, current_user: user)}
    else
      _ ->
        {:error, :unauthorized}
    end
  end

  @impl true
  def id(socket), do: socket.assigns[:current_user].id
end
