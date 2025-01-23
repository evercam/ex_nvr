defmodule ExNVRWeb.OnvifDiscoveryLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  require Logger

  alias Ecto.Changeset
  alias Onvif.{Devices, Media}
  alias Onvif.Devices.Schemas.NetworkInterface
  alias Onvif.Media.Ver20.Schemas.Profile.VideoEncoder

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
              snapshot_uri: nil,
              edit_mode: false,
              video_encoder_options: [],
              update_form: nil,
              video_encoder_view_options: []
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
            sub_stream_uri: sub_stream.stream_uri
          }

        [main_stream] ->
          %{stream_uri: main_stream.stream_uri, snapshot_uri: main_stream.snapshot_uri}

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

  def handle_event(
        "switch-profile-edit-mode",
        %{"token" => profile_token, "edit" => edit},
        socket
      ) do
    device_details = socket.assigns.device_details

    media_profiles =
      Enum.map(device_details.media_profiles, fn media_profile ->
        if media_profile.profile.reference_token == profile_token do
          %{media_profile | edit_mode: String.to_existing_atom(edit)}
        else
          media_profile
        end
      end)

    {:noreply,
     assign(socket, :device_details, %{device_details | media_profiles: media_profiles})}
  end

  def handle_event("encoding-change", params, socket) do
    device_details = socket.assigns.device_details

    media_profile =
      Enum.find(device_details.media_profiles, &Map.has_key?(params, &1.profile.reference_token))

    token = media_profile.profile.reference_token
    encoding = String.to_existing_atom(params[token]["encoding"])

    updated_media_profile = get_video_encoder_view_options(media_profile, encoding)

    device_details.media_profiles
    |> Enum.map(fn media_profile ->
      if media_profile.profile.reference_token == token,
        do: updated_media_profile,
        else: media_profile
    end)
    |> then(&Map.put(device_details, :media_profiles, &1))
    |> then(&{:noreply, assign(socket, device_details: &1)})
  end

  def handle_event("update-profile", params, socket) do
    %{media_profiles: media_profiles} = device_details = socket.assigns.device_details
    media_profile = Enum.find(media_profiles, &Map.has_key?(params, &1.profile.reference_token))
    params = params[media_profile.profile.reference_token]

    params =
      Map.update!(params, "resolution", fn value ->
        [width, height] = String.split(value, "|", parts: 2)
        %{"width" => width, "height" => height}
      end)

    with {:ok, video_encoder} <- validate_encoder_params(media_profile, params),
         {:ok, _response} <-
           Media.Ver20.SetVideoEncoderConfiguration.request(
             device_details.onvif_device,
             [video_encoder]
           ) do
      {:noreply, assign(socket, device_details: get_profiles(device_details))}
    else
      {:error, reason} ->
        Logger.error(
          "Error occurred while updating video encoder configuration: #{inspect(reason)}"
        )

        {:noreply, put_flash(socket, :error, "could not update video encoder configuration")}
    end
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
        |> Enum.map(fn profile ->
          %MediaProfile{profile: profile, edit_mode: false}
          |> fetch_snapshot_and_stream_uris(details.onvif_device)
          |> get_video_encoder_options(details.onvif_device)
          |> media_profile_to_form()
          |> get_video_encoder_view_options()
        end)
        |> then(&%CameraDetails{details | media_profiles: &1})

      _error ->
        details
    end
  end

  defp fetch_snapshot_and_stream_uris(
         %MediaProfile{profile: profile} = media_profile,
         onvif_device
       ) do
    {:ok, stream_uri} = Media.Ver20.GetStreamUri.request(onvif_device, [profile.reference_token])

    {:ok, snapshot_uri} =
      Media.Ver10.GetSnapshotUri.request(onvif_device, [profile.reference_token])

    %{media_profile | snapshot_uri: snapshot_uri, stream_uri: stream_uri}
  end

  defp get_video_encoder_options(%{profile: profile} = media_profile, onvif_device) do
    options =
      case Media.Ver20.GetVideoEncoderConfigurationOptions.request(onvif_device, [
             nil,
             profile.reference_token
           ]) do
        {:ok, options} -> options
        _error -> []
      end

    %{media_profile | video_encoder_options: options}
  end

  defp media_profile_to_form(media_profile) do
    encoder_config = media_profile.profile.video_encoder_configuration

    update_form =
      to_form(VideoEncoder.changeset(encoder_config, %{}),
        as: media_profile.profile.reference_token
      )

    %{media_profile | update_form: update_form}
  end

  defp get_video_encoder_view_options(media_profile, encoding \\ nil) do
    codec = encoding || media_profile.update_form[:encoding].value
    config = Enum.find(media_profile.video_encoder_options, &(&1.encoding == codec))

    resolutions =
      Enum.map(
        config.resolutions_available,
        &{"#{&1.width} x #{&1.height}", "#{&1.width}|#{&1.height}"}
      )
      |> Enum.reverse()

    %{
      media_profile
      | video_encoder_view_options: %{
          profiles: config.profiles_supported,
          gov_length_min: List.first(config.gov_length_range),
          gov_length_max: List.last(config.gov_length_range),
          quality_min: config.quality_range.min,
          quality_max: config.quality_range.max,
          resolutions: resolutions,
          bitrate_min: config.bitrate_range.min,
          bitrate_max: config.bitrate_range.max,
          frame_rates: config.frame_rates_supported
        }
    }
  end

  defp validate_encoder_params(%MediaProfile{profile: profile}, params) do
    profile.video_encoder_configuration
    |> VideoEncoder.changeset(params)
    |> Ecto.Changeset.apply_action(:update)
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

  defp codecs(media_profile) do
    Enum.map(
      media_profile.video_encoder_options,
      &{to_string(&1.encoding) |> String.upcase(), &1.encoding}
    )
    |> Enum.reverse()
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
