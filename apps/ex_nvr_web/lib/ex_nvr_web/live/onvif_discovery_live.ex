defmodule ExNVRWeb.OnvifDiscoveryLive do
  @moduledoc false

  require Logger
  use ExNVRWeb, :live_view

  require Membrane.Logger

  alias Ecto.Changeset
  alias ExNVR.Devices
  alias ExNVR.Model.Device

  @default_discovery_settings %{
    "timeout" => 5
  }

  @default_device_details_settings %{
    "username" => nil,
    "password" => nil
  }

  @step_titles %{
    1 => "Discover Devices",
    2 => "Device Details",
    3 => "Manage stream profiles"
  }

  def mount(_params, _session, socket) do
    socket
    |> assign_discovery_form()
    |> assign_device_details_form()
    |> assign_discovered_devices()
    |> assign(
      step: 1,
      step_titles: @step_titles,
      network_scanned: false,
      selected_device: nil,
      device_details: nil,
      device_details_cache: %{}
    )
    |> then(&{:ok, &1})
  end

  def handle_event("discover", %{"discover_settings" => params}, socket) do
    with {:ok, %{timeout: timeout}} <- validate_discover_params(params),
         {:ok, discovered_devices} <- Devices.discover(:timer.seconds(timeout)) do
      socket
      |> assign(:network_scanned, true)
      |> assign_discovery_form(params)
      |> assign_discovered_devices(discovered_devices)
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

  def handle_event("select-device", %{"url" => device_url}, socket) do
    device = Enum.find(socket.assigns.discovered_devices, &(&1.url == device_url))

    {:noreply, assign(socket, selected_device: device)}
  end

  def handle_event("device-details", %{"device_details_settings" => params}, socket) do
    fetch_device_details(socket, params)
  end

  def handle_event("add-device", _params, socket) do
    selected_device = socket.assigns.selected_device
    device_details = socket.assigns.device_details
    device_details_form_params = socket.assigns.device_details_form.params

    stream_config =
      case device_details.media_profiles do
        [main_stream, sub_stream | _rest] ->
          main_stream
          |> Map.take([:stream_uri, :snapshot_uri])
          |> Map.put(:sub_stream_uri, sub_stream.stream_uri)

        [main_stream] ->
          Map.take(main_stream, [:stream_uri, :snapshot_uri])

        _other ->
          %{}
      end

    device_info = device_details.device_information

    socket
    |> put_flash(:device_params, %{
      name: selected_device.name,
      type: :ip,
      vendor: device_info.manufacturer,
      model: device_info.model,
      mac: device_details.network_interface.mac_address,
      url: selected_device.url,
      stream_config: stream_config,
      credentials: %{
        username: device_details_form_params["username"],
        password: device_details_form_params["password"]
      }
    })
    |> redirect(to: ~p"/devices/new")
    |> then(&{:noreply, &1})
  end

  def handle_event("to-previous-step", _params, socket) do
    {:noreply, assign(socket, step: socket.assigns.step - 1)}
  end

  def handle_event("create-profile", _params, socket) do
    form_data = %{
      "name" => "",
      "encoding" => "",
      "resolution" => "",
      "fps" => "",
      "videobitrate" => ""
    }

    socket
    |> assign(profile_form: to_form(form_data), step: 3)
    |> then(&{:noreply, &1})
  end

  def handle_event("save-profile", params, socket) do
    device_details = socket.assigns.device_details
    selected_device = socket.assigns.selected_device
    device_details_form_params = socket.assigns.device_details_form.params

    device = %Device{
      vendor: device_details.device_information.manufacturer,
      url: selected_device.url,
      credentials: %Device.Credentials{
        username: device_details_form_params["username"],
        password: device_details_form_params["password"]
      }
    }

    case Devices.create_stream_profile(device, params) do
      :ok ->
        socket
        |> put_flash(:info, "Profile created successfully")
        |> assign(device_details_cache: %{})
        |> fetch_device_details(device_details_form_params)

      :error ->
        socket
        |> put_flash(:error, "An error occured during profile creation")
        |> assign(step: 2)
        |> then(&{:noreply, &1})
    end
  end

  defp fetch_device_details(socket, device_details_form_params) do
    device = socket.assigns.selected_device
    device_details_cache = socket.assigns.device_details_cache

    case Map.fetch(device_details_cache, device.url) do
      {:ok, device_details} ->
        socket
        |> assign_device_details_form(device_details_form_params)
        |> assign(selected_device: device, device_details: device_details, step: 2)
        |> then(&{:noreply, &1})

      :error ->
        opts = [
          username: device_details_form_params["username"],
          password: device_details_form_params["password"]
        ]

        device_details =
          device.url
          |> Devices.fetch_camera_details(opts)
          |> map_date_time()
          |> select_network_interface()

        socket
        |> assign_device_details_form(device_details_form_params)
        |> assign(
          selected_device: device,
          device_details: device_details,
          device_details_cache: Map.put(device_details_cache, device.url, device_details),
          step: 2
        )
        |> then(&{:noreply, &1})
    end
  end

  defp assign_discovery_form(socket, params \\ nil) do
    assign(
      socket,
      :discover_form,
      to_form(params || @default_discovery_settings, as: :discover_settings)
    )
  end

  defp assign_device_details_form(socket, params \\ nil) do
    assign(
      socket,
      :device_details_form,
      to_form(params || @default_device_details_settings, as: :device_details_settings)
    )
  end

  defp assign_discovered_devices(socket, devices \\ []) do
    assign(socket, :discovered_devices, devices)
  end

  defp validate_discover_params(params) do
    types = %{timeout: :integer}

    {%{}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.validate_required([:timeout])
    |> Changeset.validate_inclusion(:timeout, 1..30)
    |> Changeset.apply_action(:create)
  end

  defp map_date_time(%{date_time_settings: settings} = device_details) when is_map(settings) do
    %{
      device_details
      | date_time_settings: %{
          type: settings[:date_time_type],
          daylight_savings: String.to_atom(settings[:daylight_savings]),
          timezone: get_in(settings, [:time_zone, :tz])
        }
    }
  end

  defp map_date_time(device_details), do: device_details

  defp select_network_interface(device_details) do
    case device_details[:network_interfaces] do
      nil ->
        device_details

      interfaces ->
        network_interface = List.first(interfaces)
        from_dhcp? = String.to_atom(get_in(network_interface, [:ip_v4, :config, :dhcp]))

        address =
          if from_dhcp? do
            get_in(network_interface, [:ip_v4, :config, :from_dhcp])
          else
            get_in(network_interface, [:ip_v4, :config, :manual])
          end

        device_details
        |> Map.delete(:network_interfaces)
        |> Map.put(:network_interface, %{
          name: get_in(network_interface, [:info, :name]),
          mac_address: get_in(network_interface, [:info, :hw_address]),
          mtu: get_in(network_interface, [:info, :mtu]),
          from_dhcp?: from_dhcp?,
          address: "#{address[:address]}/#{address[:prefix_length]}"
        })
    end
  end

  defp display_key(key) do
    to_string(key)
    |> String.split("_")
    |> Enum.map_join(" ", &Macro.camelize/1)
  end
end
