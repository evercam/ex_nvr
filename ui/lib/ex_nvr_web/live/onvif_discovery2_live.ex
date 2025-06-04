defmodule ExNVRWeb.OnvifDiscovery2Live do
  @moduledoc false

  use ExNVRWeb, :live_view

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

    defstruct [:name, :probe, :device, :auth_form]
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

      <div class="w-3/4 flex flex-col space-y-5 bg-white p-5 border rounded-lg dark:border-gray-600 dark:bg-gray-950 dark:text-white mr-5">
        <span class="text-md font-bold">
          <.icon name="hero-wifi" class="w-5 h-5 mr-1" /> Found {length(@devices)} Device(s)
        </span>
        <div :for={device <- @devices} id={device.probe.device_ip} class="flex flex-col space-y-2">
          <div class="flex justify-between border-2 rounded-lg dark:border-gray-500 p-5">
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
            <.button :if={not is_nil(device.device)}>
              <.icon name="hero-check-circle" class="w-4 h-4" />View Details
            </.button>
          </div>
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

    {:noreply, assign(socket, devices: devices)}
  end

  def handle_event("authenticate-device", params, socket) do
    devices = socket.assigns.devices
    IO.inspect(params)

    if idx = Enum.find_index(devices, &(&1.probe.device_ip == params["id"])) do
      camera_details = Enum.at(devices, idx)

      case Onvif.Device.init(camera_details.probe, params["username"], params["password"]) do
        {:ok, onvif_device} ->
          camera_details = %CameraDetails{camera_details | device: onvif_device}

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

  defp assign_discover_settings(socket, settings) do
    discover_form = to_form(DiscoverSettings.create_changeset(settings))
    assign(socket, discover_settings: settings, discover_form: discover_form)
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
end
