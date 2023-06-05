defmodule ExNVRWeb.API.DeviceController do
  @moduledoc false

  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController

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
end
