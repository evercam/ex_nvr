defmodule ExNVRWeb.API.SystemStatusController do
  @moduledoc false

  use ExNVRWeb, :controller

  import ExNVR.Authorization

  alias ExNVR.SystemStatus

  action_fallback ExNVRWeb.API.FallbackController

  def status(conn, _params) do
    user = conn.assigns.current_user

    with :ok <- authorize(user, :system, :read) do
      json(conn, SystemStatus.get())
    end
  end
end
