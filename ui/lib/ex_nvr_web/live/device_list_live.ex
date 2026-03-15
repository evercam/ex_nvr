defmodule ExNVRWeb.DeviceListLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  alias ExNVR.Devices
  alias ExNVR.Triggers

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
        <:col :let={device} label="Triggers">
          <span :if={@trigger_counts[device.id]} class="inline-flex items-center rounded-full bg-blue-100 px-2.5 py-0.5 text-xs font-medium text-blue-800 dark:bg-blue-900 dark:text-blue-200">
            {@trigger_counts[device.id]} active
          </span>
          <span :if={!@trigger_counts[device.id]} class="text-gray-400 dark:text-gray-500 text-sm">
            None
          </span>
        </:col>
      </.table>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, devices: Devices.list(), trigger_counts: Triggers.trigger_config_counts_by_device())}
  end

  defp get_type_label(:ip), do: "IP Camera"
  defp get_type_label(:file), do: "File"
  defp get_type_label(:webcam), do: "Webcam"
end
