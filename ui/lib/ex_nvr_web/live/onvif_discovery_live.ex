defmodule ExNVRWeb.OnvifDiscoveryLive do
  @moduledoc false

  require Logger
  use ExNVRWeb, :live_view

  require Membrane.Logger

  alias Ecto.Changeset
  alias Onvif.{Devices, Discovery, Media}

  @scope_regex ~r[^onvif://www.onvif.org/(name|hardware)/(.*)]

  @default_discovery_settings %{
    "username" => nil,
    "password" => nil,
    "timeout" => 5
  }

  def mount(_params, _session, socket) do
    socket
    |> assign_discovery_form()
    |> assign_discovered_devices()
    |> assign(selected_device: nil, device_details: nil, device_details_cache: %{})
    |> then(&{:ok, &1})
  end

  def handle_event("discover", %{"discover_settings" => params}, socket) do
    with {:ok, %{timeout: timeout} = validated_params} <- validate_discover_params(params),
         discovered_devices <- Discovery.probe(probe_timeout: :timer.seconds(timeout)) do
      onvif_devices =
        Enum.map(
          discovered_devices,
          &get_onvif_device(&1, validated_params.username, validated_params.password)
        )

      socket
      |> assign_discovery_form(params)
      |> assign_discovered_devices(onvif_devices)
      |> then(&{:noreply, &1})
    else
      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_discovery_form(socket, changeset)}
    end
  end

  def handle_event("device-details", %{"url" => device_url}, socket) do
    device = Enum.find(socket.assigns.discovered_devices, &(&1.address == device_url))
    device_details_cache = socket.assigns.device_details_cache

    case Map.fetch(device_details_cache, device.address) do
      {:ok, device_details} ->
        {:noreply, assign(socket, selected_device: device, device_details: device_details)}

      :error ->
        device_details = fetch_onvif_details(device)

        {:noreply,
         assign(socket,
           selected_device: device,
           device_details: device_details,
           device_details_cache: Map.put(device_details_cache, device_url, device_details)
         )}
    end
  end

  def handle_event("add-device", _params, socket) do
    selected_device = socket.assigns.selected_device
    device_details = socket.assigns.device_details

    stream_config =
      case device_details.media_profiles do
        [main_stream, sub_stream | _rest] ->
          {_profile, main_stream_uri, main_snapshot_uri} = main_stream
          {_profile, sub_stream_uri, _sub_snapshot_uri} = sub_stream

          %{
            stream_uri: main_stream_uri,
            snapshot_uri: main_snapshot_uri,
            sub_stream_uri: sub_stream_uri
          }

        [{_profile, stream_uri, snapshot_uri}] ->
          %{stream_uri: stream_uri, snapshot_uri: snapshot_uri}

        _other ->
          %{}
      end

    socket
    |> put_flash(:device_params, %{
      name: scope_value(selected_device.scopes, "name"),
      type: :ip,
      vendor: selected_device.manufacturer,
      model: selected_device.model,
      mac: device_details.network_interface.info.hw_address,
      url: selected_device.address,
      stream_config: stream_config,
      credentials: %{username: selected_device.username, password: selected_device.password}
    })
    |> redirect(to: ~p"/devices/new")
    |> then(&{:noreply, &1})
  end

  defp assign_discovery_form(socket, params \\ nil) do
    assign(
      socket,
      :discover_form,
      to_form(params || @default_discovery_settings, as: :discover_settings)
    )
  end

  defp assign_discovered_devices(socket, devices \\ []) do
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

  defp get_onvif_device(probe, username, password)
       when not is_nil(username) and not is_nil(password) do
    case Onvif.Device.init(probe, username, password) do
      {:ok, device} -> device
      _error -> get_onvif_device(probe, nil, nil)
    end
  end

  defp get_onvif_device(probe, _username, _password) do
    probe.address
    |> List.first()
    |> Onvif.Device.new(nil, nil)
    |> Map.put(:scopes, probe.scopes)
  end

  defp fetch_onvif_details(onvif_device) do
    details = %{
      network_interface: nil,
      media_profiles: []
    }

    details =
      case Devices.GetNetworkInterfaces.request(onvif_device) do
        {:ok, interfaces} -> Map.put(details, :network_interface, List.first(interfaces))
        _error -> details
      end

    case Media.Ver20.GetProfiles.request(onvif_device) do
      {:ok, profiles} ->
        profiles
        |> Enum.sort(&(&1.name <= &2.name))
        |> Enum.map(&fetch_snapshot_and_stream_uris(onvif_device, &1))
        |> then(&Map.put(details, :media_profiles, &1))

      _error ->
        details
    end
  end

  defp fetch_snapshot_and_stream_uris(onvif_device, %Media.Ver20.Profile{} = profile) do
    {:ok, stream_uri} = Media.Ver20.GetStreamUri.request(onvif_device, [profile.reference_token])

    {:ok, snapshot_uri} =
      Media.Ver10.GetSnapshotUri.request(onvif_device, [profile.reference_token])

    {profile, stream_uri, snapshot_uri}
  end

  # View functions
  defp scope_value(scopes, scope_key) do
    scopes
    |> Enum.flat_map(&Regex.scan(@scope_regex, &1, capture: :all_but_first))
    |> Enum.find(fn [key, _value] -> key == scope_key end)
    |> case do
      [_key, value] -> URI.decode(value)
      _other -> nil
    end
  end

  defp ip_address(%Onvif.Device.NetworkInterface{ipv4: ipv4}) do
    if ipv4.config.dhcp, do: ipv4.config.from_dhcp.address, else: ipv4.config.manual.address
  end
end
