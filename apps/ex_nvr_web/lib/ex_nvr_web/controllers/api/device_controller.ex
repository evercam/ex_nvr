defmodule ExNVRWeb.API.DeviceController do
  @moduledoc false

  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController

  plug ExNVRWeb.Plug.Device, [field_name: "id"] when action == :update

  alias ExNVR.{Devices, Pipelines}
  alias Plug.Conn

  @spec create(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def create(%Conn{} = conn, params) do
    with {:ok, device} <- Devices.create(params) do
      if Application.get_env(:ex_nvr, :run_pipelines, true),
        do: Pipelines.Supervisor.start_pipeline(device)

      conn
      |> put_status(201)
      |> render(:show, device: device)
    end
  end

  @spec update(Conn.t(), map()) :: Conn.t() | {:error, Ecto.Changeset.t()}
  def update(%Conn{} = conn, params) do
    device = conn.assigns.device

    with {:ok, device} <- Devices.update(device, params) do
      if Application.get_env(:ex_nvr, :run_pipelines, true),
        do: Pipelines.Supervisor.restart_pipeline(device)

      render(conn, :show, device: device)
    end
  end
end
