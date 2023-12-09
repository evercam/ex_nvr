defmodule ExNVRWeb.OnvifDiscoveryLive do
  @moduledoc false

  require Logger
  use ExNVRWeb, :live_view

  require Membrane.Logger

  alias Ecto.Changeset
  alias ExNVR.Onvif

  @default_discovery_settings %{
    "username" => nil,
    "password" => nil,
    "timeout" => 5
  }

  @default_device_details %{
    infos: nil,
    time_settings: nil,
    network_interface: nil,
    media_profiles: [],
    snapshot_uri: nil
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
         {:ok, discovered_devices} <- Onvif.discover(timeout: :timer.seconds(timeout)) do
      socket
      |> assign_discovery_form(params)
      |> assign_discovered_devices(
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

  def handle_event("device-details", %{"name" => device_name}, socket) do
    device = Enum.find(socket.assigns.discovered_devices, &(&1.name == device_name))
    device_details_cache = socket.assigns.device_details_cache

    case Map.fetch(device_details_cache, device.name) do
      {:ok, device_details} ->
        {:noreply, assign(socket, selected_device: device, device_details: device_details)}

      :error ->
        opts = [username: device.username, password: device.password]

        media_url =
          get_in(Onvif.call!(device.url, :get_capabilities), [
            :GetCapabilitiesResponse,
            :Capabilities,
            :Media,
            :XAddr
          ])

        device_details =
          @default_device_details
          |> fetch_device_info(device.url, opts)
          |> fetch_date(device.url)
          |> fetch_network_settings(device.url, opts)
          |> fetch_media_profiles(media_url, opts)
          |> fetch_stream_uris(media_url, opts)
          |> fetch_snapshot_uri(media_url, opts)

        {:noreply,
         assign(socket,
           selected_device: device,
           device_details: device_details,
           device_details_cache: Map.put(device_details_cache, device_name, device_details)
         )}
    end
  end

  def handle_event("add-device", _params, socket) do
    selected_device = socket.assigns.selected_device
    device_details = socket.assigns.device_details

    %{stream_uri: stream_uri} = Enum.at(device_details.media_profiles, 0, %{stream_uri: nil})
    %{stream_uri: sub_stream_uri} = Enum.at(device_details.media_profiles, 1, %{stream_uri: nil})

    socket
    |> put_flash(:device_params, %{
      name: selected_device.name,
      type: :ip,
      stream_config: %{
        stream_uri: stream_uri,
        sub_stream_uri: sub_stream_uri,
        snapshot_uri: device_details.snapshot_uri
      },
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

  defp fetch_device_info(device_details, url, opts) do
    response = Onvif.call(url, :get_device_information, %{}, opts)

    handle_response(
      device_details,
      response,
      "GetDeviceInformation",
      &map_device_information_response/2
    )
  end

  defp fetch_date(device_details, url) do
    response = Onvif.call(url, :get_system_date_and_time)
    handle_response(device_details, response, "GetSystemDateAndTime", &map_date_time_response/2)
  end

  defp fetch_network_settings(device_details, url, opts) do
    response = Onvif.call(url, :get_network_interfaces, %{}, opts)

    handle_response(
      device_details,
      response,
      "GetNetworkInterfaces",
      &map_network_interface_response/2
    )
  end

  defp fetch_media_profiles(device_details, url, opts) do
    response = Onvif.call(url, :get_profiles, %{"Type" => "All"}, opts)
    handle_response(device_details, response, "GetProfiles", &map_profiles_response/2)
  end

  defp fetch_stream_uris(%{media_profiles: profiles} = device_details, url, opts) do
    profiles =
      Enum.map(profiles, fn profile ->
        body = %{"ProfileToken" => profile.id, "Protocol" => ""}

        stream_uri =
          get_in(Onvif.call!(url, :get_stream_uri, body, opts), [
            :GetStreamUriResponse,
            :Uri
          ])

        %{profile | stream_uri: stream_uri}
      end)

    %{device_details | media_profiles: profiles}
  end

  defp fetch_snapshot_uri(%{media_profiles: [%{id: profile_id} | _]} = device_details, url, opts) do
    body = %{"ProfileToken" => profile_id}

    response = Onvif.call(url, :get_snapshot_uri, body, opts)

    handle_response(
      device_details,
      response,
      "GetSystemDateAndTime",
      &map_snapshot_uri_response/2
    )
  end

  defp handle_response(device_details, {:error, error}, operation, _mapper) do
    Logger.error("""
    OnvifDiscovery: could not perform #{operation}
    #{inspect(error)}
    """)

    device_details
  end

  defp handle_response(device_details, {:ok, response}, _operation, mapper) do
    mapper.(device_details, response)
  end

  defp map_device_information_response(device_details, %{
         GetDeviceInformationResponse: device_information
       }) do
    %{
      device_details
      | infos: %{
          manufacturer: device_information[:Manufacturer],
          model: device_information[:Model],
          serial_number: device_information[:SerialNumber]
        }
    }
  end

  defp map_date_time_response(device_details, %{GetSystemDateAndTimeResponse: time_settings}) do
    time_settings = time_settings[:SystemDateAndTime]

    %{
      device_details
      | time_settings: %{
          type: time_settings[:DateTimeType],
          daylight_savings: String.to_atom(time_settings[:DaylightSavings]),
          timezone: get_in(time_settings, [:TimeZone, :TZ])
        }
    }
  end

  defp map_network_interface_response(device_details, %{
         GetNetworkInterfacesResponse: network_interfaces
       })
       when is_list(network_interfaces) do
    map_network_interface_response(device_details, List.first(network_interfaces) |> elem(1))
  end

  defp map_network_interface_response(device_details, %{
         GetNetworkInterfacesResponse: network_interface
       }) do
    map_network_interface_response(
      device_details,
      network_interface[:NetworkInterfaces]
    )
  end

  defp map_network_interface_response(device_details, network_interface) do
    from_dhcp? = String.to_atom(get_in(network_interface, [:IPv4, :Config, :DHCP]))

    address =
      if from_dhcp? do
        get_in(network_interface, [:IPv4, :Config, :FromDHCP])
      else
        get_in(network_interface, [:IPv4, :Config, :Manual])
      end

    %{
      device_details
      | network_interface: %{
          name: get_in(network_interface, [:Info, :Name]),
          mac_address: get_in(network_interface, [:Info, :HwAddress]),
          mtu: get_in(network_interface, [:Info, :MTU]),
          from_dhcp?: from_dhcp?,
          address: "#{address[:Address]}/#{address[:PrefixLength]}"
        }
    }
  end

  defp map_profiles_response(device_details, %{GetProfilesResponse: profiles}) do
    profiles =
      Keyword.values(profiles)
      |> Enum.map(fn profile ->
        video_encoder = get_in(profile, [:Configurations, :VideoEncoder])
        resolution = video_encoder[:Resolution]
        rate_control = video_encoder[:RateControl]

        %{
          id: profile[:token],
          name: profile[:Name],
          codec: video_encoder[:Encoding],
          profile: video_encoder[:Profile],
          gov_length: video_encoder[:GovLength],
          resolution: %{width: resolution[:Width], height: resolution[:Height]},
          quality: video_encoder[:Quality],
          rate_control: %{
            constant_bit_rate: String.to_atom(rate_control[:ConstantBitRate]),
            frame_rate: rate_control[:FrameRateLimit],
            max_bit_rate: rate_control[:BitrateLimit]
          },
          stream_uri: nil
        }
      end)

    %{device_details | media_profiles: profiles}
  end

  defp map_snapshot_uri_response(device_details, %{GetSnapshotUriResponse: snapshot_uri_response}) do
    snapshot_uri = snapshot_uri_response[:Uri]

    %{device_details | snapshot_uri: snapshot_uri}
  end

  defp display_key(key) do
    to_string(key)
    |> String.split("_")
    |> Enum.map_join(" ", &Macro.camelize/1)
  end
end
