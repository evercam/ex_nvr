defmodule ExNVRWeb.API.DeviceController do
  @moduledoc false

  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController

  plug ExNVRWeb.Plug.Device, [field_name: "id"] when action in [:update, :show, :delete]

  import ExNVR.Authorization

  alias ExNVR.Devices
  alias Plug.Conn

  @spec create(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def create(%Conn{} = conn, params) do
    user = conn.assigns.current_user

    with :ok <- authorize(user, :device, :create),
         {:ok, device} <- Devices.create(params) do
      conn
      |> put_status(201)
      |> render(:show, device: device, user: conn.assigns.current_user)
    end
  end

  @spec update(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def update(%Conn{} = conn, params) do
    device = conn.assigns.device
    user = conn.assigns.current_user

    with :ok <- authorize(user, :device, :update),
         {:ok, device} <- Devices.update(device, params) do
      render(conn, :show, device: device, user: conn.assigns.current_user)
    end
  end

  def delete(%Conn{} = conn, _params) do
    device = conn.assigns.device
    user = conn.assigns.current_user

    with :ok <- authorize(user, :device, :delete),
         :ok <- Devices.delete(device) do
      send_resp(conn, 204, "")
    end
  end

  @spec index(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def index(%Conn{} = conn, params) do
    render(conn, :list, devices: Devices.list(params), user: conn.assigns.current_user)
  end

  @spec show(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def show(%Conn{} = conn, _params) do
    render(conn, :show, device: conn.assigns.device, user: conn.assigns.current_user)
  end
end
