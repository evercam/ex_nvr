defmodule ExNVRWeb.DeviceListLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  import ExNVR.Authorization

  alias ExNVR.Devices
  alias ExNVR.Model.Device

  def render(assigns) do
    ~H"""
    <div class="grow px-4 py-6">
      <div :if={@current_user.role == :admin} class="ml-4 sm:ml-0">
        <.link href={~p"/devices/new"}>
          <.button><.icon name="hero-plus-solid" class="h-4 w-4" />Add Device</.button>
        </.link>
      </div>

      <.table
        id="devices"
        rows={@devices}
        row_click={fn device -> JS.navigate(~p"/devices/#{device.id}/details") end}
        row_id={fn device -> "device-row-#{device.id}" end}
      >
        <:col :let={device} label="Id">
          <div class="flex items-center gap-2">
            <span id={"device-id-#{device.id}"}>{device.id}</span>
            <button
              type="button"
              phx-click={JS.dispatch("events:clipboard-copy", to: "#device-id-#{device.id}")}
              class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-200"
              title="Copy ID"
            >
              <.icon name="hero-clipboard-document" class="h-4 w-4 copy-icon" />
              <.icon name="hero-check" class="h-4 w-4 copied-icon hidden" />
            </button>
          </div>
        </:col>
        <:col :let={device} label="Type">{get_type_label(device.type)}</:col>
        <:col :let={device} label="Name">{device.name}</:col>
        <:col :let={device} label="Vendor">{device.vendor || "N/A"}</:col>
        <:col :let={device} label="Timezone">{device.timezone}</:col>
        <:col :let={device} label="State">
          <div class="flex items-center">
            <div class={
              ["h-2.5 w-2.5 rounded-full mr-2"] ++
                case device.state do
                  :recording -> ["bg-green-500"]
                  :streaming -> ["bg-green-500"]
                  :failed -> ["bg-red-500"]
                  :stopped -> ["bg-yellow-500"]
                end
            }>
            </div>
            {String.upcase(to_string(device.state))}
          </div>
        </:col>
        <:action :let={device}>
          <.three_dot
            :if={@current_user.role == :admin}
            id={"dropdownMenuIconButton_#{device.id}"}
            dropdown_id={"dropdownDots_#{device.id}"}
          />
          <div
            id={"dropdownDots_#{device.id}"}
            class="z-10 hidden text-left bg-white divide-y divide-gray-100 rounded-lg shadow w-44 dark:bg-gray-700 dark:divide-gray-600"
          >
            <ul
              class="py-2 text-sm text-gray-700 dark:text-gray-200"
              aria-labelledby={"dropdownMenuIconButton_#{device.id}"}
            >
              <li>
                <.link
                  :if={not Device.recording?(device)}
                  phx-click="start-recording"
                  phx-value-device={device.id}
                  class="block px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
                >
                  Start recording
                </.link>
              </li>
              <li>
                <.link
                  :if={Device.recording?(device)}
                  phx-click="stop-recording"
                  phx-value-device={device.id}
                  class="block px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
                >
                  Stop recording
                </.link>
              </li>
            </ul>
          </div>
        </:action>
      </.table>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, devices: Devices.list())}
  end

  def handle_event("stop-recording", %{"device" => device_id}, socket) do
    user = socket.assigns.current_user

    case authorize(user, :device, :update) do
      :ok -> update_device_state(socket, device_id, :stopped)
      {:error, :unauthorized} -> unauthorized(socket, :noreply)
    end
  end

  def handle_event("start-recording", %{"device" => device_id}, socket) do
    user = socket.assigns.current_user

    case authorize(user, :device, :update) do
      :ok -> update_device_state(socket, device_id, :recording)
      {:error, :unauthorized} -> unauthorized(socket, :noreply)
    end
  end

  defp update_device_state(socket, device_id, new_state) do
    devices = socket.assigns.devices

    with %Device{} = device <- Enum.find(devices, &(&1.id == device_id)),
         {:ok, _device} <- Devices.update_state(device, new_state) do
      {:noreply, assign(socket, devices: Devices.list())}
    else
      _other -> {:noreply, put_flash(socket, :error, "could not update device state")}
    end
  end

  defp get_type_label(:ip), do: "IP Camera"
  defp get_type_label(:file), do: "File"
  defp get_type_label(:webcam), do: "Webcam"

  defp unauthorized(socket, reply) do
    socket
    |> put_flash(:error, "You are not authorized to perform this action!")
    |> then(&{reply, &1})
  end
end
