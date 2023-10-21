defmodule ExNVRWeb.API.DeviceController do
  @moduledoc false

  use ExNVRWeb, :controller
  use Permit.Phoenix.Controller,
    authorization_module: ExNVR.Authorization,
    resource_module: ExNVR.Model.Device

  action_fallback ExNVRWeb.API.FallbackController

  plug ExNVRWeb.Plug.Device, [field_name: "id"] when action in [:update, :show]

  alias ExNVR.{Devices, DeviceSupervisor}
  alias ExNVR.Model.Device
  alias Plug.Conn

  @impl true
  def handle_unauthorized(_action, conn) do
    conn
    |> put_status(401)
    |> json(%{message: "You do not have permission to perform this action."})
  end

  @spec create(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def create(%Conn{} = conn, params) do
    with {:ok, device} <- Devices.create(params) do
      if Device.recording?(device) do
        DeviceSupervisor.start(device)
      end

      conn
      |> put_status(201)
      |> render(:show, device: device)
    end
  end

  @spec update(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def update(%Conn{} = conn, params) do
    device = conn.assigns.device

    with {:ok, updated_device} <- Devices.update(device, params) do
      cond do
        device.state != updated_device.state and not Device.recording?(updated_device.state) ->
          DeviceSupervisor.stop(updated_device)

        device.state != updated_device.state and Device.recording?(updated_device.state) ->
          DeviceSupervisor.start(updated_device)

        Device.config_updated(device, updated_device) and Device.recording?(updated_device.state) ->
          DeviceSupervisor.restart(updated_device)

        true ->
          :ok
      end

      render(conn, :show, device: device)
    end
  end

  @spec index(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def index(%Conn{} = conn, params) do
    render(conn, :list, devices: Devices.list(params))
  end

  @spec show(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def show(%Conn{} = conn, _params) do
    render(conn, :show, device: conn.assigns.device)
  end
end
