defmodule ExNVRWeb.DeviceDetailsLive do
  use ExNVRWeb, :live_view

  require Logger

  alias ExNVR.Devices
  alias ExNVRWeb.DeviceTabs.{EventsListTab, RecordingsListTab}
  alias ExNVRWeb.Router.Helpers, as: Routes

  @impl true
  def mount(%{"id" => device_id} = params, _session, socket) do
    device = Devices.get!(device_id)

    active_tab = params["tab"] || "details"

    {:ok,
     assign(socket,
       device: device,
       active_tab: active_tab,
       params: params,
       files_details: %{}
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:active_tab, params["tab"] || socket.assigns.active_tab)
     |> assign(:params, params)}
  end

  @impl true
  def handle_info({:tab_changed, %{tab: tab}}, socket) do
    params =
      socket.assigns.params
      |> Map.put("tab", tab)
      |> Map.put("filter_params", %{})

    {:noreply,
     socket
     |> assign(:active_tab, tab)
     |> assign(:params, params)
     |> push_patch(
       to: Routes.device_details_path(socket, :show, socket.assigns.device.id, params)
     )}
  end

  @impl true
  def handle_info(_msg, socket) do
    Map.merge(socket.assigns.filter_params, socket.assigns.pagination_params)
    |> Map.merge(socket.assigns.sort_params)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grow px-4 py-6">
      <h2 class="text-xl font-semibold text-black dark:text-white mb-4">
        Device: {@device.name}
      </h2>
      <.tabs id="device-details-tabs" active_tab={@active_tab} on_change={:tab_changed}>
        <:tab id="details" label="Details" />
        <:tab id="recordings" label="Recordings" />
        <:tab id="stats" label="Stats" />
        <:tab id="settings" label="Settings" />
        <:tab id="events" label="Events" />
        
    <!-- device details tab -->
        <:tab_content for="details">
          <ul class="divide-y divide-gray-700 text-white rounded-md shadow-sm max-w-xl ">
            <li class="p-4 flex justify-between items-center">
              <span class="font-semibold text-gray-400">Name:</span>
              <span>{@device.name}</span>
            </li>
            <li class="p-4 flex justify-between items-center">
              <span class="font-semibold text-gray-400">Type:</span>
              <span>{@device.type}</span>
            </li>
            <li class="p-4 flex justify-between items-center">
              <span class="font-semibold text-gray-400">Status:</span>
              <span class="font-bold flex items-center gap-1">
                <div class={
                  ["h-2.5 w-2.5 rounded-full mr-2"] ++
                    case @device.state do
                      :recording -> ["bg-green-500"]
                      :streaming -> ["bg-green-500"]
                      :failed -> ["bg-red-500"]
                      :stopped -> ["bg-yellow-500"]
                    end
                }>
                </div>
                {String.upcase(to_string(@device.state))}
              </span>
            </li>
            <li class="p-4 flex justify-between items-center">
              <span class="font-semibold text-gray-400">Created At:</span>
              <span>{Calendar.strftime(@device.inserted_at, "%b %d, %Y %H:%M:%S %Z")}</span>
            </li>
            <li class="p-4 flex justify-between items-center">
              <span class="font-semibold text-gray-400">Timezone:</span>
              <span>{@device.timezone}</span>
            </li>
          </ul>
        </:tab_content>
        
    <!-- recordings tab -->
        <:tab_content for="recordings">
          <.live_component
            module={RecordingsListTab}
            id="recording_list_tab"
            device={@device}
            params={@params}
          />
        </:tab_content>
        
    <!-- stats tab-->
        <:tab_content for="stats">
          <div class="text-center text-gray-500 dark:text-gray-400">Stats tab coming soon...</div>
        </:tab_content>

        <:tab_content for="settings">
          <div class="text-center text-gray-500 dark:text-gray-400">
            Settings tab comming soon....
          </div>
        </:tab_content>
        
    <!-- events tab-->
        <:tab_content for="events">
          <.live_component
            id="events_lists_tab"
            module={EventsListTab}
            device={@device}
            params={@params}
          />
        </:tab_content>
      </.tabs>
    </div>
    """
  end
end
