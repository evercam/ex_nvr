defmodule ExNVRWeb.API.OnvifController do
  @moduledoc false

  use ExNVRWeb, :controller

  import ExNVR.Authorization

  alias Ecto.Changeset

  action_fallback ExNVRWeb.API.FallbackController

  @default_timeout 5

  def discover(conn, params) do
    with :ok <- authorize(conn.assigns.current_user, :onvif, :discover),
         {:ok, params} <- validate_discover_query_params(params),
         {:ok, devices} <- ExNVR.Devices.discover(:timer.seconds(params.timeout)) do
      result =
        Enum.map(
          devices,
          &Map.merge(&1, ExNVR.Devices.fetch_camera_details(&1.url, Keyword.new(params)))
        )

      json(conn, result)
    end
  end

  defp validate_discover_query_params(params) do
    types = %{timeout: :integer, username: :string, password: :string}

    {%{timeout: @default_timeout}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.validate_number(:timeout, less_than_or_equal_to: 60, greater_than: 0)
    |> Changeset.apply_action(:insert)
  end
end
