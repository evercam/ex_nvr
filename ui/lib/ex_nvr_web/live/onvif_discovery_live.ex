defmodule ExNVRWeb.OnvifDiscoveryLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  require Logger

  alias Ecto.Changeset
  alias Onvif.{Devices, Media}
  alias Onvif.Devices.Schemas.NetworkInterface

  @scope_regex ~r[^onvif://www.onvif.org/(name|hardware)/(.*)]

  @default_discovery_settings %{
    "username" => nil,
    "password" => nil,
    "timeout" => 2,
    "ip_addr" => nil
  }

  defmodule MediaProfile do
    defstruct profile: nil,
              stream_uri: nil,
              snapshot_uri: nil
  end

  defmodule CameraDetails do
    defstruct onvif_device: nil, network_interface: nil, media_profiles: []
  end

  def mount(_params, _session, socket) do
    socket
    |> assign_discovery_form()
    |> assign_discovered_devices()
    |> then(&{:ok, &1})
  end

  def handle_event("discover", %{"discover_settings" => params}, socket) do
    with {:ok, validated_params} <- validate_discover_params(params),
         discovered_devices <-
           ExNVR.Devices.discover(
             probe_timeout: to_timeout(second: validated_params[:timeout]),
             ip_address: validated_params[:ip_addr]
           ) do
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
          %{
            stream_uri: main_stream.stream_uri,
            snapshot_uri: main_stream.snapshot_uri,
            profile_token: main_stream.profile.reference_token,
            sub_stream_uri: sub_stream.stream_uri,
            sub_snapshot_uri: sub_stream.snapshot_uri,
            sub_profile_token: sub_stream.profile.reference_token
          }

        [main_stream] ->
          %{
            stream_uri: main_stream.stream_uri,
            snapshot_uri: main_stream.snapshot_uri,
            profile_token: main_stream.profile.reference_token
          }

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

  def handle_event("reorder-profiles", %{"token" => token, "direction" => direction}, socket) do
    socket.assigns.device_details
    |> Map.update!(:media_profiles, &do_reorder_profiles(&1, token, direction))
    |> then(&{:noreply, assign(socket, device_details: &1)})
  end

  def handle_info({:profile_updated, reference_token}, socket) do
    device_details = socket.assigns.device_details
    onvif_device = socket.assigns.selected_device

    {:ok, [profile]} = Media.Ver20.GetProfiles.request(onvif_device, [reference_token])

    {:noreply,
     assign(socket,
       device_details: update_media_profile(device_details, reference_token, :profile, profile)
     )}
  end

  def handle_info({key, reference_token, value}, socket)
      when key in [:stream_uri, :snapshot_uri] do
    device_details =
      update_media_profile(
        socket.assigns.device_details,
        reference_token,
        key,
        value
      )

    {:noreply, assign(socket, device_details: device_details)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp assign_discovery_form(socket, params \\ nil) do
    assign(
      socket,
      :discover_form,
      to_form(params || @default_discovery_settings, as: :discover_settings)
    )
  end

  defp assign_discovered_devices(socket, devices \\ []) do
    assign(socket,
      discovered_devices: devices,
      selected_device: nil,
      device_details: nil,
      device_details_cache: %{}
    )
  end

  defp validate_discover_params(params) do
    types = %{username: :string, password: :string, timeout: :integer, ip_addr: :string}

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
    %Onvif.Device{
      address: List.first(probe.address),
      manufacturer: scope_value(probe.scopes, "hardware"),
      model: scope_value(probe.scopes, "name"),
      username: "",
      password: "",
      scopes: probe.scopes
    }
  end

  defp fetch_onvif_details(onvif_device) do
    %CameraDetails{onvif_device: onvif_device}
    |> get_network_interface()
    |> get_profiles()
  end

  defp get_network_interface(%CameraDetails{} = details) do
    case Devices.GetNetworkInterfaces.request(details.onvif_device) do
      {:ok, interfaces} -> %CameraDetails{details | network_interface: List.first(interfaces)}
      _error -> details
    end
  end

  defp get_profiles(details) do
    case Media.Ver20.GetProfiles.request(details.onvif_device) do
      {:ok, profiles} ->
        profiles
        |> Enum.reverse()
        |> Enum.map(&%MediaProfile{profile: &1})
        |> then(&%CameraDetails{details | media_profiles: &1})

      _error ->
        details
    end
  end

  defp do_reorder_profiles([], _token, _direction), do: []

  defp do_reorder_profiles([head | tail], token, direction) do
    tail
    |> Enum.reduce([head], fn media_profile1, [media_profile2 | rest] ->
      %{profile: p1} = media_profile1
      %{profile: p2} = media_profile2

      cond do
        direction == "down" and p2.reference_token == token ->
          [media_profile2, media_profile1 | rest]

        direction == "up" and p1.reference_token == token ->
          [media_profile2, media_profile1 | rest]

        true ->
          [media_profile1, media_profile2 | rest]
      end
    end)
    |> Enum.reverse()
  end

  defp update_media_profile(device_details, reference_token, key, value) do
    device_details.media_profiles
    |> Enum.map(fn media_profile ->
      if media_profile.profile.reference_token == reference_token,
        do: Map.put(media_profile, key, value),
        else: media_profile
    end)
    |> then(&Map.put(device_details, :media_profiles, &1))
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

  defp ip_address(%NetworkInterface{ipv4: ipv4}) do
    if ipv4.config.dhcp, do: ipv4.config.from_dhcp.address, else: ipv4.config.manual.address
  end

  defp ip_addresses() do
    case :inet.getifaddrs() do
      {:ok, if_addrs} ->
        if_addrs
        |> Enum.reject(fn {_name, options} -> is_nil(options[:addr]) end)
        |> Enum.map(fn {name, options} ->
          addr = :inet.ntoa(options[:addr]) |> List.to_string()
          {"#{name} - #{addr}", addr}
        end)

      _error ->
        []
    end
  end
end

defimpl Phoenix.HTML.Safe, for: Onvif.Media.Ver20.Schemas.Profile.VideoEncoder.Resolution do
  def to_iodata(%{width: width, height: height}), do: "#{width}|#{height}"
end
