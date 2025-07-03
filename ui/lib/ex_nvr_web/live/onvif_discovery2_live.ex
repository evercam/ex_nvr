defmodule ExNVRWeb.OnvifDiscovery2Live do
  @moduledoc false

  use ExNVRWeb, :live_view

  require Logger

  alias ExNVR.Devices.Cameras.{NetworkInterface, NTP, StreamProfile}
  alias ExNVRWeb.Onvif.StreamProfile2

  defmodule DiscoverSettings do
    @moduledoc false

    use Ecto.Schema

    alias Ecto.Changeset

    embedded_schema do
      field :ip_address, :string
      field :timeout, :integer
    end

    def to_struct(params) do
      params |> changeset() |> Changeset.apply_action(:validate)
    end

    def create_changeset(struct), do: changeset(struct, %{})

    def changeset(changeset \\ %__MODULE__{}, params) do
      changeset
      |> Changeset.cast(params, [:ip_address, :timeout])
      |> Changeset.validate_required([:timeout])
      |> Changeset.validate_number(:timeout, greater_than: 0, less_than_or_equal_to: 60)
    end
  end

  defmodule CameraDetails do
    @moduledoc false

    defstruct [
      :name,
      :probe,
      :device,
      :network_interface,
      :ntp,
      :stream_profiles,
      :auth_form,
      :streams_form,
      :selected_profiles,
      tab: "system"
    ]
  end

  def render(assigns) do
    ~H"""
    <div class="w-full flex items-center flex-col space-y-5">
      <div class="w-full flex items-center flex-col bg-white dark:bg-gray-700">
        <div class="w-3/4 flex justify-between items-center ">
          <div>
            <h1 class="text-2xl font-bold dark:text-white">Onvif Camera Manager</h1>
            <p class="text-sm text-gray-400">Discover and manage network cameras</p>
          </div>

          <.simple_form
            id="discover_settings_form"
            for={@discover_form}
            phx-change="discover-settings"
          >
            <div class="border flex flex-col dark:text-white p-5 m-5 space-y-4 rounded-lg dark:border-black dark:bg-gray-950">
              <span class="font-bold"><.icon name="hero-cog-6-tooth" /> Network Settings</span>
              <div class="flex items-center gap-2">
                <.input
                  field={@discover_form[:ip_address]}
                  type="select"
                  name="ip_address"
                  options={ip_addresses()}
                  prompt="Choose IP address to use"
                  label="IP Address"
                />
                <.input
                  field={@discover_form[:timeout]}
                  type="number"
                  name="timeout"
                  min="1"
                  label="Timeout"
                />
              </div>
            </div>
          </.simple_form>
        </div>
      </div>
      
    <!-- Device Discovery Section -->
      <div class="w-3/4 flex justify-between items-center bg-white p-5 border rounded-lg dark:border-gray-600 dark:bg-gray-950 dark:text-white mr-5">
        <div class="flex items-center space-x-2">
          <.icon name="network" class="row-span-2 h-6 w-6" />
          <div class="flex flex-col">
            <span class="text-xl font-bold">Device Discovery</span>
            <span class="text-sm dark:text-gray-400">
              Scanning: {@discover_settings.ip_address} • Timeout {@discover_settings.timeout}s
            </span>
          </div>
        </div>

        <.button phx-click="discover" phx-disable-with="Scanning...">
          <.icon name="hero-magnifying-glass-solid" class="w-4 h-4 mr-2" /> Scan Network
        </.button>
      </div>
      
    <!-- Device List Section -->
      <div class="w-3/4 flex flex-col space-y-5 bg-white p-5 border rounded-lg dark:border-gray-600 dark:bg-gray-950 dark:text-white mr-5">
        <span class="text-md font-bold">
          <.icon name="hero-wifi" class="w-5 h-5 mr-1" /> Found {length(@devices)} Device(s)
        </span>
        <div :for={device <- @devices} id={device.probe.device_ip} class="flex flex-col space-y-2">
          <div class="flex justify-between border rounded-lg dark:border-gray-200 p-5">
            <div class="flex items-center">
              <div class="boder-1 rounded-lg bg-gray-200 dark:bg-gray-600 p-2 mr-2">
                <.icon name="hero-camera" class="w-6 h-6" />
              </div>
              <div class="flex flex-col">
                <span class="text-md font-bold">{device.name}</span>
                <div class="text-sm text-gray-500">
                  <span class="mr-3">{device.probe.device_ip}</span>
                </div>
              </div>
            </div>
            <.button
              :if={is_nil(device.device)}
              class="bg-white dark:bg-gray-950 border dark:border-gray-600"
              phx-click={
                show_modal2(
                  JS.set_attribute({"phx-value-id", device.probe.device_ip}, to: "#auth-form"),
                  "camera-authentication"
                )
              }
            >
              <.icon name="hero-lock-closed" class="w-4 h-4" />Authenticate
            </.button>
            <.button
              :if={not is_nil(device.device)}
              phx-click="show-details"
              phx-value-id={device.probe.device_ip}
            >
              <.icon name="hero-check-circle" class="w-4 h-4" />View Details
            </.button>
          </div>
        </div>
      </div>

      <.separator :if={@selected_device} class="w-3/4 mr-5" />
      
    <!-- Device Details Section -->
      <div :if={@selected_device} class="w-3/4 flex flex-col space-y-2 mr-5">
        <div class="flex justify-between items-center border rounded-lg bg-white dark:border-gray-600 dark:bg-gray-950 dark:text-white p-5">
          <div class="flex items-center">
            <div class="boder-1 rounded-lg bg-gray-200 dark:bg-gray-600 p-2 mr-2">
              <.icon name="hero-camera" class="w-7 h-7" />
            </div>
            <div class="flex flex-col">
              <span class="text-lg font-bold">{@selected_device.name}</span>
              <div class="text-sm text-gray-500">
                <span class="mr-3">{@selected_device.probe.device_ip}</span>
                <span class="mr-3">{@selected_device.device.manufacturer}</span>
              </div>
            </div>
          </div>
          <.button phx-click="add-device">
            <.icon name="hero-plus" class="w-4 h-4" />Add to NVR
          </.button>
        </div>

        <div class="grid grid-cols-4 content-center rounded-lg bg-white dark:border-gray-600 dark:bg-gray-700 dark:text-white p-1">
          <div class={["flex justify-center", selected_tab("system", @selected_device.tab)]}>
            <span
              class="text-sm font-bold p-1 hover:cursor-pointer"
              phx-click="switch-tab"
              phx-value-tab="system"
            >
              <.icon name="hero-information-circle" class="w-5 h-5 mr-1" />System
            </span>
          </div>
          <div class={["flex justify-center", selected_tab("network", @selected_device.tab)]}>
            <span
              class="text-sm font-bold p-1 hover:cursor-pointer"
              phx-click="switch-tab"
              phx-value-tab="network"
            >
              <.icon name="network" class="w-4 h-4 mr-1 text-black dark:text-white inline" />Network
            </span>
          </div>
          <div class={["flex justify-center", selected_tab("datetime", @selected_device.tab)]}>
            <span
              class="text-sm font-bold p-1 hover:cursor-pointer"
              phx-click="switch-tab"
              phx-value-tab="datetime"
            >
              <.icon name="hero-clock" class="w-4 h-4 mr-1" />Date & Time
            </span>
          </div>
          <div class={["flex justify-center", selected_tab("streams", @selected_device.tab)]}>
            <span
              class="text-sm font-bold p-1 hover:cursor-pointer"
              phx-click="switch-tab"
              phx-value-tab="streams"
            >
              <.icon name="hero-tv" class="w-4 h-4 mr-1" />Streams
            </span>
          </div>
        </div>

        <div
          :if={@selected_device.tab == "system"}
          class="w-1/2 flex flex-col border rounded-lg bg-white dark:border-gray-600 dark:bg-gray-950 dark:text-white"
        >
          <h2 class="text-lg font-bold p-3">Hardware Information</h2>
          <div class="space-y-2 p-5 pt-0 text-sm">
            <div class="flex justify-between">
              <span class="text-gray-600">Manufacturer:</span>
              <span class="font-mono">{@selected_device.device.manufacturer}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-600">Model:</span>
              <span class="font-mono">{@selected_device.device.model}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-600">Firmware:</span>
              <span class="font-mono">{@selected_device.device.firmware_version}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-600">Hardware ID:</span>
              <span class="font-mono">{@selected_device.device.hardware_id}</span>
            </div>
          </div>
        </div>

        <div
          :if={@selected_device.tab == "network"}
          class="flex flex-col border rounded-lg bg-white dark:border-gray-600 dark:bg-gray-950 dark:text-white"
        >
          <h2 class="text-lg font-bold p-3">Network Configuration</h2>
          <div class="space-y-2 p-5 pt-0 text-sm">
            <div class="grid grid-cols-2 gap-x-6 gap-y-2">
              <div class="flex justify-between">
                <span class="text-gray-600">Name:</span>
                <span class="font-mono">{@selected_device.network_interface.name}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-600">IP Address:</span>
                <span class="font-mono">{@selected_device.network_interface.ipv4.address}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-600">MAC Address:</span>
                <span class="font-mono">{@selected_device.network_interface.hw_address}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-600">DHCP:</span>
                <.tag>{format_dhcp(@selected_device.network_interface.ipv4.dhcp)}</.tag>
              </div>
            </div>
          </div>
        </div>

        <div
          :if={@selected_device.tab == "datetime"}
          class="flex flex-col border rounded-lg bg-white dark:border-gray-600 dark:bg-gray-950 dark:text-white"
        >
          <h2 class="text-lg font-bold p-3">Date & Time Settings</h2>
          <div class="space-y-2 p-5 pt-0 text-sm">
            <div class="grid grid-cols-2 gap-x-6 gap-y-2">
              <div class="flex justify-between">
                <span class="text-gray-600">Timezone:</span>
                <span class="font-mono">{@selected_device.device.system_date_time.time_zone.tz}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-600">NTP Enabled</span>
                <.tag>{yes_no(@selected_device.ntp)}</.tag>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-600">Dayligth Saving</span>
                <.tag>
                  {yes_no(@selected_device.device.system_date_time.daylight_savings)}
                </.tag>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-600">NTP Server</span>
                <span class="font-mono">
                  {@selected_device.ntp && @selected_device.ntp.server}
                </span>
              </div>
            </div>
          </div>
        </div>

        <div
          :if={@selected_device.tab == "streams"}
          class="flex flex-col border rounded-lg bg-white dark:border-gray-600 dark:bg-gray-950 dark:text-white"
        >
          <h2 class="text-lg font-bold p-3">Stream Selection</h2>
          <div class="space-y-2 p-5 pt-0 text-sm">
            <.simple_form
              id="stream_selection_form"
              for={@selected_device.streams_form}
              phx-change="update-selected-stream"
            >
              <div class="grid grid-cols-2 gap-x-5">
                <.input
                  field={@selected_device.streams_form[:main_stream]}
                  type="select"
                  name="main_stream"
                  options={stream_options(@selected_device.stream_profiles)}
                  label="Main Stream"
                />

                <.input
                  field={@selected_device.streams_form[:sub_stream]}
                  type="select"
                  name="sub_stream"
                  options={stream_options(@selected_device.stream_profiles)}
                  label="Sub Stream"
                  prompt=""
                />
              </div>
            </.simple_form>
          </div>
        </div>
        <div :if={@selected_device.tab == "streams"} class="grid grid-cols-2 gap-x-5">
          <StreamProfile2.stream_profile
            :for={{profile, idx} <- Enum.with_index(@selected_device.selected_profiles)}
            id={"#{profile.id}-#{idx}"}
            profile={profile}
          />
        </div>
      </div>
    </div>

    <.modal2 id="camera-authentication">
      <:header>Sign in</:header>
      <.simple_form id="auth-form" phx-submit="authenticate-device" for={@auth_form} class="space-y-4">
        <.input
          field={@auth_form[:username]}
          name="username"
          id="username"
          placeholder="admin"
          label="Your username"
          required
        />
        <.input
          field={@auth_form[:password]}
          type="password"
          name="password"
          id="password"
          placeholder="••••••••"
          label="Your password"
          class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-600 dark:border-gray-500 dark:placeholder-gray-400 dark:text-white"
          required
        />
        <div class="flex items-center space-x-5">
          <.button
            type="button"
            class="w-full bg-white dark:bg-gray-800 border dark:border-gray-600"
            phx-click={hide_modal2("camera-authentication")}
          >
            Cancel
          </.button>
          <.button class="w-full" type="submit" phx-disable-with="Authenticating...">Connect</.button>
        </div>
      </.simple_form>
    </.modal2>
    """
  end

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_discover_settings(%DiscoverSettings{timeout: 2})
      |> assign(devices: [], auth_form: to_form(%{"username" => nil, "password" => nil}))
      |> assign(selected_device: nil)

    {:ok, socket}
  end

  def handle_event("discover-settings", params, socket) do
    case DiscoverSettings.to_struct(params) do
      {:ok, settings} ->
        {:noreply, assign_discover_settings(socket, settings)}

      {:error, changeset} ->
        {:noreply, assign(socket, discover_form: to_form(changeset))}
    end
  end

  def handle_event("discover", _params, socket) do
    settings = socket.assigns.discover_settings

    devices =
      ExNVR.Devices.Onvif.discover(
        ip_address: settings.ip_address,
        timeout: :timer.seconds(settings.timeout)
      )
      |> Enum.map(&%CameraDetails{probe: &1, name: scope_value(&1.scopes, "name")})

    {:noreply, assign(socket, devices: devices, selected_device: nil)}
  end

  def handle_event("authenticate-device", params, socket) do
    devices = socket.assigns.devices

    if idx = Enum.find_index(devices, &(&1.probe.device_ip == params["id"])) do
      camera_details = Enum.at(devices, idx)

      case Onvif.Device.init(camera_details.probe, params["username"], params["password"]) do
        {:ok, onvif_device} ->
          camera_details =
            %CameraDetails{camera_details | device: onvif_device}
            |> get_network_interface()
            |> get_ntp()
            |> get_stream_profiles()
            |> set_streams_form()

          socket =
            socket
            |> push_event("js-exec", %{to: "#camera-authentication", attr: "data-cancel"})
            |> assign(devices: List.replace_at(devices, idx, camera_details))

          {:noreply, socket}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Invalid credentials")}
      end
    else
      {:noreply, put_flash(socket, :error, "could not find device with id: #{params["id"]}")}
    end
  end

  def handle_event("show-details", params, socket) do
    devices = socket.assigns.devices

    if device = Enum.find(devices, &(&1.probe.device_ip == params["id"])) do
      {:noreply, assign(socket, selected_device: device)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("switch-tab", %{"tab" => tab}, socket) do
    device = %{socket.assigns.selected_device | tab: tab}
    {:noreply, assign(socket, selected_device: device)}
  end

  def handle_event("update-selected-stream", params, socket) do
    selected_device = socket.assigns.selected_device
    main_stream = Enum.find(selected_device.stream_profiles, &(&1.id == params["main_stream"]))
    sub_stream = Enum.find(selected_device.stream_profiles, &(&1.id == params["sub_stream"]))

    selected_device = %{
      selected_device
      | selected_profiles: Enum.reject([main_stream, sub_stream], &is_nil/1)
    }

    {:noreply, assign(socket, selected_device: selected_device)}
  end

  def handle_event("add-device", _params, socket) do
    selected_device = socket.assigns.selected_device
    %{username: username, password: password} = selected_device.device

    stream_config =
      case selected_device.selected_profiles do
        [main_stream, sub_stream] ->
          %{
            stream_uri: main_stream.stream_uri,
            snapshot_uri: main_stream.snapshot_uri,
            profile_token: main_stream.id,
            sub_stream_uri: sub_stream.stream_uri,
            sub_snapshot_uri: sub_stream.snapshot_uri,
            sub_profile_token: sub_stream.id
          }

        [main_stream] ->
          %{
            stream_uri: main_stream.stream_uri,
            snapshot_uri: main_stream.snapshot_uri,
            profile_token: main_stream.id
          }

        _other ->
          %{}
      end

    socket
    |> put_flash(:device_params, %{
      name: selected_device.name,
      type: :ip,
      vendor: selected_device.device.manufacturer,
      model: selected_device.device.model,
      mac: selected_device.network_interface && selected_device.network_interface.hw_address,
      url: selected_device.device.address,
      stream_config: stream_config,
      credentials: %{username: username, password: password}
    })
    |> redirect(to: ~p"/devices/new")
    |> then(&{:noreply, &1})
  end

  defp assign_discover_settings(socket, settings) do
    discover_form = to_form(DiscoverSettings.create_changeset(settings))
    assign(socket, discover_settings: settings, discover_form: discover_form)
  end

  defp get_network_interface(camera_details) do
    case Onvif.Devices.get_network_interfaces(camera_details.device) do
      {:ok, interfaces} ->
        %{camera_details | network_interface: NetworkInterface.from_onvif(List.first(interfaces))}

      {:error, reason} ->
        Logger.error("Failed to get network interfaces for camera #{inspect(reason)}")
        camera_details
    end
  end

  defp get_ntp(%{device: %{system_date_time: %{date_time_type: :ntp}}} = camera_details) do
    case Onvif.Devices.get_ntp(camera_details.device) do
      {:ok, ntp} ->
        %{camera_details | ntp: NTP.from_onvif(ntp)}

      {:error, reason} ->
        Logger.error("Failed to get ntp settings for camera #{inspect(reason)}")
        camera_details
    end
  end

  defp get_ntp(camera_details), do: camera_details

  defp get_stream_profiles(%{device: %{media_ver20_service_path: nil}} = camera_details) do
    Logger.warning("[OnvifDiscovery] camera does not support onvif media version 2")
    camera_details
  end

  defp get_stream_profiles(camera_details) do
    case Onvif.Media2.get_profiles(camera_details.device) do
      {:ok, profiles} ->
        %{camera_details | stream_profiles: Enum.map(profiles, &StreamProfile.from_onvif/1)}
        |> get_stream_uris()

      {:error, reason} ->
        Logger.error("Failed to get stream profiles for camera #{inspect(reason)}")
        camera_details
    end
  end

  defp get_stream_uris(%{device: device} = camera_details) do
    profiles =
      Enum.map(camera_details.stream_profiles, fn profile ->
        with {:ok, stream_uri} <- Onvif.Media2.get_stream_uri(device, profile.id),
             {:ok, snapshot_uri} <- Onvif.Media2.get_snapshot_uri(device, profile.id) do
          %{profile | stream_uri: stream_uri, snapshot_uri: snapshot_uri}
        else
          _error ->
            profile
        end
      end)

    %{camera_details | stream_profiles: profiles}
  end

  defp set_streams_form(%{stream_profiles: profiles} = camera_details) do
    main_stream = Enum.at(profiles, 0)
    sub_stream = Enum.at(profiles, 1)

    streams_form =
      to_form(%{
        "main_stream" => main_stream && main_stream.id,
        "sub_stream" => sub_stream && sub_stream.id
      })

    selected_profiles = Enum.reject([main_stream, sub_stream], &is_nil/1)

    %{camera_details | streams_form: streams_form, selected_profiles: selected_profiles}
  end

  # view functions
  defp ip_addresses do
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

  defp scope_value(scopes, scope_key) do
    regex = ~r[^onvif://www.onvif.org/(name|hardware)/(.*)]

    scopes
    |> Enum.flat_map(&Regex.scan(regex, &1, capture: :all_but_first))
    |> Enum.find(fn [key, _value] -> key == scope_key end)
    |> case do
      [_key, value] -> URI.decode(value)
      _other -> nil
    end
  end

  defp selected_tab(tab, tab), do: ["rounded-sm", "bg-gray-300", "dark:bg-gray-950"]
  defp selected_tab(_, _), do: []

  defp format_dhcp(true), do: "Enabled"
  defp format_dhcp(false), do: "Disabled"

  defp yes_no(nil), do: "No"
  defp yes_no(false), do: "No"
  defp yes_no(_other), do: "Yes"

  defp stream_options(stream_profiles) do
    Enum.map(stream_profiles, &{&1.name, &1.id})
  end
end
