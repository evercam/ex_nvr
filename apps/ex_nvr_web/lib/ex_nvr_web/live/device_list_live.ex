defmodule ExNVRWeb.DeviceListLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  import ExNVR.Authorization

  alias ExNVR.Model.Device
  alias ExNVR.{Devices, DeviceSupervisor}

  def render(assigns) do
    ~H"""
    <div class="grow">
      <div class="ml-4 sm:ml-0">
        <.link href={~p"/devices/new"}>
          <.button>Add device</.button>
        </.link>
      </div>

      <.table id="devices" rows={@devices}>
        <:col :let={device} label="Id"><%= device.id %></:col>
        <:col :let={device} label="Type"><%= get_type_label(device.type) %></:col>
        <:col :let={device} label="Name"><%= device.name %></:col>
        <:col :let={device} label="Timezone"><%= device.timezone %></:col>
        <:col :let={device} label="State">
          <div class="flex items-center">
            <div class={
              ["h-2.5 w-2.5 rounded-full mr-2"] ++
                case device.state do
                  :recording -> ["bg-green-500"]
                  :failed -> ["bg-red-500"]
                  :stopped -> ["bg-yellow-500"]
                end
            }>
            </div>
            <%= String.upcase(to_string(device.state)) %>
          </div>
        </:col>
        <:action :let={device}>
          <.button
            id={"dropdownMenuIconButton_#{device.id}"}
            data-dropdown-toggle={"dropdownDots_#{device.id}"}
            class="text-sm ml-3 hover:bg-gray-100 dark:bg-gray-800"
          >
            <svg
              class="w-5 h-5"
              aria-hidden="true"
              fill="currentColor"
              viewBox="0 0 20 20"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path d="M10 6a2 2 0 110-4 2 2 0 010 4zM10 12a2 2 0 110-4 2 2 0 010 4zM10 18a2 2 0 110-4 2 2 0 010 4z" />
            </svg>
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
                    href={~p"/devices/#{device.id}"}
                    class="block px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
                  >
                    Update
                  </.link>
                </li>
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
          </.button>
        </:action>
      </.table>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    role = socket.assigns.current_user.role

    if can(role) |> read?(Device) do
      {:ok, assign(socket, devices: Devices.list())}
    else
      socket
      |> put_flash(:error, "You are not authorized to perform this action!")
      |> redirect(to: ~p"/dashboard")
      |> then(&{:ok, &1})
    end
  end

  def handle_event("stop-recording", %{"device" => device_id}, socket) do
    role = socket.assigns.current_user.role

    if can(role) |> update?(Device) do
      update_device_state(socket, device_id, :stopped)
    else
      socket
      |> put_flash(:error, "You are not authorized to perform this action!")
      |> redirect(to: ~p"/devices")
      |> then(&{:noreply, &1})
    end
  end

  def handle_event("start-recording", %{"device" => device_id}, socket) do
    role = socket.assigns.current_user.role

    if can(role) |> update?(Device) do
      update_device_state(socket, device_id, :recording)
    else
      socket
      |> put_flash(:error, "You are not authorized to perform this action!")
      |> redirect(to: ~p"/devices")
      |> then(&{:noreply, &1})
    end
  end

  defp update_device_state(socket, device_id, new_state) do
    devices = socket.assigns.devices

    with %Device{} = device <- Enum.find(devices, &(&1.id == device_id)),
         {:ok, device} <- Devices.update_state(device, new_state) do
      if new_state == :recording,
        do: DeviceSupervisor.start(device),
        else: DeviceSupervisor.stop(device)

      {:noreply, assign(socket, devices: Devices.list())}
    else
      _other -> {:noreply, put_flash(socket, :error, "could not update device state")}
    end
  end

  defp get_type_label(:ip), do: "IP Camera"
  defp get_type_label(:file), do: "File"
end
