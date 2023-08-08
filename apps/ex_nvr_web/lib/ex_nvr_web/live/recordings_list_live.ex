defmodule ExNVRWeb.RecordingListLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  alias ExNVR.Model.Device
  alias ExNVR.{Devices, Recordings, Pipelines}

  def render(assigns) do
    ~H"""
    <div class="grow">
      <.table id="recordings" rows={@recordings}>
        <:col :let={recording} label="Id"><%= recording.id %></:col>
        <:col :let={recording} label="Device"><%= recording.device.name %></:col>
        <:col :let={recording} label="Filename"><%= recording.filename %></:col>
        <:col :let={recording} label="Start-date"><%= recording.start_date %></:col>
        <:col :let={recording} label="End-date"><%= recording.end_date %></:col>
        <:action :let={recording}>
          <.button
            id={"dropdownMenuIconButton_#{recording.id}"}
            data-dropdown-toggle={"dropdownDots_#{recording.id}"}
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
              id={"dropdownDots_#{recording.id}"}
              class="z-10 hidden text-left bg-white divide-y divide-gray-100 rounded-lg shadow w-44 dark:bg-gray-700 dark:divide-gray-600"
            >
              <ul
                class="py-2 text-sm text-gray-700 dark:text-gray-200"
                aria-labelledby={"dropdownMenuIconButton_#{recording.id}"}
              >
                <li>
                  <.link
                    href={~p"/devices/#{recording.device.id}"}
                    class="block px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
                  >
                    Update
                  </.link>
                </li>
                <li>
                  <.link
                    phx-click="download-recording"
                    phx-value-device={recording.id}
                    class="block px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
                  >
                    Download
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
    {:ok, assign(socket, recordings: Recordings.list())}
  end

  def handle_event("stop-recording", %{"device" => device_id}, socket) do
    update_device_state(socket, device_id, :stopped)
  end

  def handle_event("start-recording", %{"device" => device_id}, socket) do
    update_device_state(socket, device_id, :recording)
  end

  defp update_device_state(socket, device_id, new_state) do
    devices = socket.assigns.devices

    with %Device{} = device <- Enum.find(devices, &(&1.id == device_id)),
         {:ok, device} <- Devices.update_state(device, new_state) do
      if new_state == :recording,
        do: Pipelines.Supervisor.start_pipeline(device),
        else: Pipelines.Supervisor.stop_pipeline(device)

      {:noreply, assign(socket, devices: Devices.list())}
    else
      _other -> {:noreply, put_flash(socket, :error, "could not update device state")}
    end
  end
end
