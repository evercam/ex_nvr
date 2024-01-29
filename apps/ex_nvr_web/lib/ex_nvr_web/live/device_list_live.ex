defmodule ExNVRWeb.DeviceListLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  import ExNVR.Authorization

  alias ExNVR.Model.Device
  alias ExNVR.{Devices, DeviceSupervisor}

  def render(assigns) do
    ~H"""
    <div class="grow">
      <div :if={@current_user.role == :admin} class="ml-4 sm:ml-0">
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
            :if={@current_user.role == :admin}
            id={"dropdownMenuIconButton_#{device.id}"}
            data-dropdown-toggle={"dropdownDots_#{device.id}"}
            class="text-sm ml-3 bg-gray-200 hover:bg-gray-200 text-zinc-900 dark:bg-gray-800 dark:hover:bg-gray-700 dark:text-gray-400"
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
                    phx-click={show_modal("delete-device-modal-#{device.id}")}
                    phx-value-device={device.id}
                    class="block px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
                  >
                    Delete
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
        <:action :let={device}>
          <.modal id={"delete-device-modal-#{device.id}"}>
            <div class="bg-blue-300 dark:bg-gray-800 m-8 rounded">
              <h2 class="text-xl text-black dark:text-white font-bold mb-4">
                Are you sure you want to delete this device? <br />
              </h2>
              <h3>
                The actual recording files are not deleted. <br />
                If you want to delete them delete the following folders: <br />
                <div class="bg-white dark:bg-gray-400 rounded-md p-4 mt-2">
                  <code class="text-gray-800 font-bold">
                    <%= Device.base_dir(device) %>
                  </code>
                </div>
              </h3>
              <div class="mt-4">
                <button
                  phx-click="delete-device"
                  phx-value-device={device.id}
                  class="bg-red-500 hover:bg-red-600 text-black dark:text-white py-2 px-4 rounded mr-4 font-bold"
                >
                  Confirm Delete
                </button>
                <button
                  phx-click={hide_modal("delete-device-modal-#{device.id}")}
                  class="bg-gray-200 hover:bg-gray-400 text-gray-800 py-2 px-4 rounded font-bold"
                >
                  Cancel
                </button>
              </div>
            </div>
          </.modal>
        </:action>
      </.table>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, devices: Devices.list())}
  end

  def handle_event("delete-device", %{"device" => device_id}, socket) do
    delete_device(socket, device_id)
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

  defp delete_device(socket, device_id) do
    devices = socket.assigns.devices
    user = socket.assigns.current_user

    with :ok <- authorize(user, :device, :delete),
         %Device{} = device <- Enum.find(devices, &(&1.id == device_id)),
         :ok <- Devices.delete(device) do
      socket =
        socket
        |> assign(devices: Devices.list())
        |> put_flash(:info, "Device #{device.name} deleted")

      {:noreply, socket}
    else
      _other -> {:noreply, put_flash(socket, :error, "could not delete device")}
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

  defp unauthorized(socket, reply) do
    socket
    |> put_flash(:error, "You are not authorized to perform this action!")
    |> then(&{reply, &1})
  end
end
