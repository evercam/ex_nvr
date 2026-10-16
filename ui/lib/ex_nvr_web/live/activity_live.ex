defmodule ExNVRWeb.ActivityLive do
  @moduledoc """
  Everything that happens in ExNVR.

    * System: events, what the system and the cameras did (webhook and system events).
    * User: activity, what users, API clients and the remote server did.
  """

  use ExNVRWeb, :live_view

  alias ExNVR.{Activity, Devices}
  alias ExNVRWeb.ActivityLive.UserActivityList
  alias ExNVRWeb.GenericEventsLive.{EventsList, WebhookConfig}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full space-y-8 mt-4">
      <.tabs id="activity-tabs" active_tab={@active_tab} on_change={:tab_changed}>
        <:tab id="system" label="System" />
        <:tab id="user" label="User" />

        <:tab_content for="system">
          <div class="flex justify-end">
            <.button id="open-webhook-settings" phx-click="open_webhook_settings">
              <.icon name="hero-cog-6-tooth" class="w-4 h-4 mr-1" /> Webhook settings
            </.button>
          </div>
          <.live_component id="events-list" module={EventsList} params={@params} devices={@devices} />
        </:tab_content>

        <:tab_content for="user">
          <.live_component
            id="user-activity"
            module={UserActivityList}
            params={@params}
            devices={@device_list}
          />
        </:tab_content>
      </.tabs>

      <.modal
        :if={@show_webhook_settings}
        id="webhook-settings"
        show
        on_cancel={JS.push("close_webhook_settings")}
      >
        <.live_component
          id="webhook-config"
          module={WebhookConfig}
          devices={@devices}
          current_user={@current_user}
        />
      </.modal>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Activity.subscribe()

    device_list = Devices.list()

    {:ok,
     socket
     |> assign(:device_list, device_list)
     |> assign(:devices, Enum.map(device_list, &{&1.name, &1.id}))
     |> assign(:show_webhook_settings, false)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # `webhook` was a tab of the generic events page, it opens the settings now.
    {active_tab, show_webhook_settings} =
      case params["tab"] do
        "user" -> {"user", false}
        "webhook" -> {"system", true}
        _system -> {"system", socket.assigns.show_webhook_settings}
      end

    {:noreply,
     socket
     |> assign(:active_tab, active_tab)
     |> assign(:show_webhook_settings, show_webhook_settings)
     |> assign(:params, Map.delete(params, "tab"))}
  end

  @impl true
  def handle_event("open_webhook_settings", _params, socket) do
    {:noreply, assign(socket, :show_webhook_settings, true)}
  end

  @impl true
  def handle_event("close_webhook_settings", _params, socket) do
    {:noreply, assign(socket, :show_webhook_settings, false)}
  end

  @impl true
  def handle_info({:tab_changed, %{tab: tab}}, socket) do
    {:noreply, push_patch(socket, to: ~p"/activity?tab=#{tab}")}
  end

  @impl true
  def handle_info({:activity_logged, entries}, socket) do
    if socket.assigns.active_tab == "user" do
      send_update(UserActivityList, id: "user-activity", new_entries: length(entries))
    end

    {:noreply, socket}
  end
end
