defmodule ExNVRWeb.DeviceListLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  alias ExNVR.Devices

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
        <:col :let={device} label="Name"><%= device.name %></:col>
        <:col label="Status">
          <div class="flex items-center">
            <div class="h-2.5 w-2.5 rounded-full bg-green-500 mr-2"></div>
            Recording
          </div>
        </:col>
        <:action :let={device}>
          <.button
            id="dropdownMenuIconButton"
            data-dropdown-toggle="dropdownDots"
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
          </.button>
          <div
            id="dropdownDots"
            class="z-10 hidden text-left bg-white divide-y divide-gray-100 rounded-lg shadow w-44 dark:bg-gray-700 dark:divide-gray-600"
          >
            <ul
              class="py-2 text-sm text-gray-700 dark:text-gray-200"
              aria-labelledby="dropdownMenuIconButton"
            >
              <li>
                <.link
                  href={~p"/devices/#{device.id}"}
                  class="block px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
                >
                  Update
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
end
