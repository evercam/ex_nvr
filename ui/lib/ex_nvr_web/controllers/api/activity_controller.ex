defmodule ExNVRWeb.API.ActivityController do
  @moduledoc false

  use ExNVRWeb, :controller

  action_fallback ExNVRWeb.API.FallbackController

  alias ExNVR.Activity
  alias Plug.Conn

  @spec index(Conn.t(), map()) :: Conn.t() | {:error, Flop.Meta.t()}
  def index(%Conn{} = conn, params) do
    device_id = conn.assigns[:device] && conn.assigns.device.id

    with {:ok, {entries, meta}} <- Activity.list(params, device_id: device_id) do
      meta = Map.take(meta, [:current_page, :page_size, :total_count, :total_pages])
      json(conn, %{meta: meta, data: entries})
    end
  end
end
