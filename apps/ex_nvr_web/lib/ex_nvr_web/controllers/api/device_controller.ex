defmodule ExNVRWeb.API.DeviceController do
  @moduledoc false

  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController

  plug ExNVRWeb.Plug.Device, [field_name: "id"] when action in [:update, :show]

  alias ExNVR.{Devices, Pipelines}
  alias ExNVR.Model.Device
  alias Plug.Conn

  @spec create(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def create(%Conn{} = conn, params) do
    with {:ok, device} <- Devices.create(params) do
      if Device.recording?(device) do
        Pipelines.Supervisor.start_pipeline(device)
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
          Pipelines.Supervisor.stop_pipeline(updated_device)

        device.state != updated_device.state and Device.recording?(updated_device.state) ->
          Pipelines.Supervisor.start_pipeline(updated_device)

        Device.config_updated(device, updated_device) and Device.recording?(updated_device.state) ->
          Pipelines.Supervisor.restart_pipeline(updated_device)

        true ->
          :ok
      end

      Pipelines.Supervisor.restart_pipeline(device)
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
