defmodule ExNVRWeb.GenericEventsLive do
  use ExNVRWeb, :live_view

  alias ExNVR.Devices
  alias ExNVRWeb.GenericEventsLive.{EventsList, WebhookConfig}
  alias ExNVRWeb.Router.Helpers, as: Routes

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full space-y-8 mt-4">
      <.tabs id="generic-events-live" active_tab={@active_tab} on_change={:tab_changed}>
        <:tab id="events" label="Events" />
        <:tab :if={admin?(@current_user)} id="webhook" label="Webhook Config" />

        <:tab_content for="events">
          <.live_component id="events-list" module={EventsList} params={@params} devices={@devices} />
        </:tab_content>

        <:tab_content :if={admin?(@current_user)} for="webhook">
          <.live_component
            id="webhook-config"
            module={WebhookConfig}
            devices={@devices}
            current_user={@current_user}
          />
        </:tab_content>
      </.tabs>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    devices = Devices.list() |> Enum.map(fn d -> {d.name, d.id} end)

    {:ok,
     socket
     |> assign(:devices, devices)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    active_tab = active_tab(socket.assigns.current_user, params["tab"])

    {:noreply,
     socket
     |> assign(:active_tab, active_tab)
     |> assign(params: params)}
  end

  @impl true
  def handle_info({:tab_changed, %{tab: tab}}, socket) do
    tab = active_tab(socket.assigns.current_user, tab)
    params = Map.put(socket.assigns.params, "tab", tab)

    {:noreply,
     socket
     |> assign(:active_tab, tab)
     |> push_patch(to: Routes.generic_events_path(socket, :index, params))}
  end

  defp active_tab(%{role: :admin}, "webhook"), do: "webhook"
  defp active_tab(_user, _tab), do: "events"

  defp admin?(user), do: user.role == :admin
end
