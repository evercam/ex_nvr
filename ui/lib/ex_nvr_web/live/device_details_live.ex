defmodule ExNVRWeb.DeviceDetailsLive do
  use ExNVRWeb, :live_view

  alias ExNVR.Devices
  alias ExNVRWeb.Router.Helpers, as: Routes

  @impl true
  def mount(%{"id" => device_id} = params, _session, socket) do
    device = Devices.get!(device_id)
    active_tab = params["tab"] || "details"

    {:ok,
     assign(socket,
       device: device,
       active_tab: active_tab,
       params: params
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
    params = Map.put(socket.assigns.params, "tab", tab)

    {:noreply,
     socket
     |> assign(:active_tab, tab)
     |> push_patch(
       to: Routes.device_details_path(socket, :show, socket.assigns.device.id, params)
     )}
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

        <:tab_content for="details">
          <div class="space-y-2 text-black dark:text-white">
            <p><strong>Name:</strong> {@device.name}</p>
            <p><strong>Type:</strong> {Atom.to_string(@device.type)}</p>
            <p><strong>Status:</strong> {Atom.to_string(@device.state)}</p>
            <p><strong>Created:</strong> {Calendar.strftime(@device.inserted_at, "%b %d, %Y %H:%M:%S %Z")}</p>
            <p><strong>Timezone:</strong> {@device.timezone}</p>
            <div class="mt-4">
              <img src={~p"/api/devices/#{@device.id}/snapshot"} class="max-w-md" />
            </div>
          </div>
        </:tab_content>

        <:tab_content for="recordings">
          <div class="text-center text-gray-500 dark:text-gray-400">Recordings tab coming soon...</div>
        </:tab_content>

        <:tab_content for="stats">
          <div class="text-center text-gray-500 dark:text-gray-400">Stats tab coming soon...</div>
        </:tab_content>

        <:tab_content for="settings">
          <div class="text-center text-gray-500 dark:text-gray-400">Settings tab coming soon...</div>
        </:tab_content>

        <:tab_content for="events">
          <div class="text-center text-gray-500 dark:text-gray-400">Events tab coming soon...</div>
        </:tab_content>
      </.tabs>
    </div>
    """
  end
end
