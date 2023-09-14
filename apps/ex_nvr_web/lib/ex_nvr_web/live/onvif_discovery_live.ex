defmodule ExNVRWeb.OnvifDiscoveryLive do
  @moduledoc false

  require Logger
  use ExNVRWeb, :live_view

  require Membrane.Logger

  alias Ecto.Changeset
  alias ExNVR.Onvif

  @default_discovery_settings %{
    "username" => "",
    "password" => "",
    "timeout" => 5
  }

  def mount(_params, _session, socket) do
    socket
    |> assign_discovery_form()
    |> assign_discoverd_devices()
    |> then(&{:ok, &1})
  end

  def handle_event("discover", %{"discover_settings" => params}, socket) do
    with {:ok, %{timeout: timeout} = validated_params} <- validate_discover_params(params),
         {:ok, discovered_devices} <- Onvif.discover(timeout: :timer.seconds(timeout)) do
      socket
      |> assign_discovery_form(params)
      |> assign_discoverd_devices(
        Enum.map(
          discovered_devices,
          &Map.merge(&1, Map.take(validated_params, [:username, :password]))
        )
      )
      |> then(&{:noreply, &1})
    else
      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_discovery_form(socket, changeset)}

      {:error, error} ->
        Logger.error("""
        OnvifDiscovery: error occurred while discovering devices
        #{inspect(error)}
        """)

        {:noreply, put_flash(socket, :error, "Error occurred while discovering devices")}
    end
  end

  defp assign_discovery_form(socket, params \\ nil) do
    assign(
      socket,
      :discover_form,
      to_form(params || @default_discovery_settings, as: :discover_settings)
    )
  end

  defp assign_discoverd_devices(socket, devices \\ []) do
    assign(socket, :discovered_devices, devices)
  end

  defp validate_discover_params(params) do
    types = %{username: :string, password: :string, timeout: :integer}

    {%{username: "", password: ""}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.validate_required([:timeout])
    |> Changeset.validate_inclusion(:timeout, 1..30)
    |> Changeset.apply_action(:create)
  end
end
