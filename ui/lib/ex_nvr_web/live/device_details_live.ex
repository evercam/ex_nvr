defmodule ExNVRWeb.DeviceDetailsLive do
  use ExNVRWeb, :live_view

  require Logger

  import ExNVR.Authorization

  alias ExNVR.Devices
  alias ExNVR.Model.Device
  alias ExNVRWeb.DeviceTabs.{EventsListTab, RecordingsListTab, SettingsTab, StatsTab, TriggersTab}
  alias ExNVRWeb.Router.Helpers, as: Routes

  @snapshot_refresh_interval to_timeout(second: 10)

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
        <:tab id="triggers" label="Triggers" />
        
    <!-- device details tab -->
        <:tab_content for="details">
          <div class="flex flex-col xl:flex-row gap-5 items-start">
            <!-- Left: info cards -->
            <div class="flex-1 min-w-0 space-y-5">
              <!-- General card -->
              <div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 shadow-sm overflow-hidden">
                <div class="px-5 py-3.5 border-b border-gray-200 dark:border-gray-700">
                  <h3 class="text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-widest">
                    General
                  </h3>
                </div>
                <dl class="divide-y divide-gray-100 dark:divide-gray-700">
                  <div class="px-5 py-3.5 flex items-center justify-between">
                    <dt class="text-sm text-gray-500 dark:text-gray-400">Name</dt>
                    <dd class="text-sm font-medium text-gray-900 dark:text-white">{@device.name}</dd>
                  </div>
                  <div class="px-5 py-3.5 flex items-center justify-between">
                    <dt class="text-sm text-gray-500 dark:text-gray-400">Type</dt>
                    <dd class="text-sm font-medium text-gray-900 dark:text-white">
                      {String.upcase(to_string(@device.type))}
                    </dd>
                  </div>
                  <div class="px-5 py-3.5 flex items-center justify-between">
                    <dt class="text-sm text-gray-500 dark:text-gray-400">Status</dt>
                    <dd class="flex items-center gap-3">
                      <span class={[
                        "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold",
                        case @device.state do
                          s when s in [:recording, :streaming] ->
                            "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400"

                          :failed ->
                            "bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400"

                          :stopped ->
                            "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-400"
                        end
                      ]}>
                        <span class={[
                          "h-1.5 w-1.5 rounded-full",
                          case @device.state do
                            s when s in [:recording, :streaming] -> "bg-green-500"
                            :failed -> "bg-red-500"
                            :stopped -> "bg-yellow-500"
                          end
                        ]}>
                        </span>
                        {String.upcase(to_string(@device.state))}
                      </span>
                      <button
                        :if={@current_user.role == :admin and Device.recording?(@device)}
                        phx-click="stop-recording"
                        class="inline-flex items-center gap-1.5 text-xs font-medium px-2.5 py-1 rounded-md bg-yellow-100 hover:bg-yellow-200 text-yellow-800 dark:bg-yellow-900/30 dark:hover:bg-yellow-900/50 dark:text-yellow-400 transition-colors"
                      >
                        <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 24 24">
                          <rect x="6" y="6" width="12" height="12" rx="1" />
                        </svg>
                        Stop
                      </button>
                      <button
                        :if={@current_user.role == :admin and not Device.recording?(@device)}
                        phx-click="start-recording"
                        class="inline-flex items-center gap-1.5 text-xs font-medium px-2.5 py-1 rounded-md bg-green-100 hover:bg-green-200 text-green-800 dark:bg-green-900/30 dark:hover:bg-green-900/50 dark:text-green-400 transition-colors"
                      >
                        <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 24 24">
                          <path d="M8 5v14l11-7z" />
                        </svg>
                        Start
                      </button>
                    </dd>
                  </div>
                  <div class="px-5 py-3.5 flex items-center justify-between">
                    <dt class="text-sm text-gray-500 dark:text-gray-400">Timezone</dt>
                    <dd class="text-sm font-medium text-gray-900 dark:text-white">
                      {@device.timezone}
                    </dd>
                  </div>
                  <div class="px-5 py-3.5 flex items-center justify-between">
                    <dt class="text-sm text-gray-500 dark:text-gray-400">Created At</dt>
                    <dd class="text-sm font-medium text-gray-900 dark:text-white">
                      {Calendar.strftime(@device.inserted_at, "%b %d, %Y · %H:%M:%S %Z")}
                    </dd>
                  </div>
                </dl>
              </div>
              
    <!-- Hardware card (only when at least one field is present) -->
              <div
                :if={@device.vendor || @device.model || @device.mac || @device.url}
                class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 shadow-sm overflow-hidden"
              >
                <div class="px-5 py-3.5 border-b border-gray-200 dark:border-gray-700">
                  <h3 class="text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-widest">
                    Hardware
                  </h3>
                </div>
                <dl class="divide-y divide-gray-100 dark:divide-gray-700">
                  <div :if={@device.vendor} class="px-5 py-3.5 flex items-center justify-between">
                    <dt class="text-sm text-gray-500 dark:text-gray-400">Vendor</dt>
                    <dd class="text-sm font-medium text-gray-900 dark:text-white">
                      {@device.vendor}
                    </dd>
                  </div>
                  <div :if={@device.model} class="px-5 py-3.5 flex items-center justify-between">
                    <dt class="text-sm text-gray-500 dark:text-gray-400">Model</dt>
                    <dd class="text-sm font-medium text-gray-900 dark:text-white">{@device.model}</dd>
                  </div>
                  <div :if={@device.mac} class="px-5 py-3.5 flex items-center justify-between">
                    <dt class="text-sm text-gray-500 dark:text-gray-400">MAC Address</dt>
                    <dd class="text-sm font-mono text-gray-900 dark:text-white">{@device.mac}</dd>
                  </div>
                  <div :if={@device.url} class="px-5 py-3.5 flex items-start justify-between gap-8">
                    <dt class="text-sm text-gray-500 dark:text-gray-400 shrink-0">URL</dt>
                    <dd class="text-sm font-mono text-gray-900 dark:text-white break-all text-right">
                      {@device.url}
                    </dd>
                  </div>
                </dl>
              </div>
            </div>
            
    <!-- Right: snapshot player -->
            <div class="w-full xl:w-[480px] shrink-0">
              <div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 shadow-sm overflow-hidden">
                <div class="px-5 py-3.5 border-b border-gray-200 dark:border-gray-700 flex items-center justify-between">
                  <h3 class="text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-widest">
                    Live Snapshot
                  </h3>
                  <span
                    :if={@snapshot_enabled}
                    class="inline-flex items-center gap-1.5 text-xs text-gray-400 dark:text-gray-500"
                  >
                    <span class="h-1.5 w-1.5 rounded-full bg-green-500 animate-pulse"></span> Live
                  </span>
                  <span
                    :if={not @snapshot_enabled and @device.state == :stopped}
                    class="text-xs font-medium text-yellow-600 dark:text-yellow-400"
                  >
                    Stopped
                  </span>
                  <span
                    :if={not @snapshot_enabled and @device.state == :failed}
                    class="text-xs font-medium text-red-500 dark:text-red-400"
                  >
                    Failed
                  </span>
                  <span
                    :if={is_nil(@device.stream_config.snapshot_uri)}
                    class="text-xs text-gray-400 dark:text-gray-500"
                  >
                    Unavailable
                  </span>
                </div>
                
    <!-- Active player -->
                <div :if={@snapshot_enabled}>
                  <div
                    :if={is_nil(@snapshot_data)}
                    class="aspect-video flex items-center justify-center bg-gray-100 dark:bg-gray-900"
                  >
                    <div class="animate-spin h-8 w-8 border-2 border-gray-300 dark:border-gray-600 border-t-blue-500 rounded-full">
                    </div>
                  </div>
                  <img
                    :if={@snapshot_data}
                    src={@snapshot_data}
                    class="w-full aspect-video object-contain bg-black"
                    alt="Live snapshot"
                  />
                  <p
                    :if={@snapshot_data}
                    class="px-4 py-2 text-xs text-center text-gray-400 dark:text-gray-500"
                  >
                    Refreshes every 10 seconds
                  </p>
                </div>
                
    <!-- Disabled placeholder -->
                <div
                  :if={not @snapshot_enabled}
                  class="aspect-video flex flex-col items-center justify-center bg-gray-100 dark:bg-gray-900 text-gray-400 dark:text-gray-600"
                >
                  <%!-- No snapshot URI configured --%>
                  <div
                    :if={is_nil(@device.stream_config.snapshot_uri)}
                    class="flex flex-col items-center"
                  >
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke-width="1.5"
                      stroke="currentColor"
                      class="w-10 h-10 mb-2"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        d="m15.75 10.5 4.72-4.72a.75.75 0 0 1 1.28.53v11.38a.75.75 0 0 1-1.28.53l-4.72-4.72M12 18.75H4.5a2.25 2.25 0 0 1-2.25-2.25V9m12.841 9.091L16.5 19.5m-1.409-1.409c.407-.407.659-.97.659-1.591v-9a2.25 2.25 0 0 0-2.25-2.25h-9c-.621 0-1.184.252-1.591.659m12.182 12.182L2.909 5.909M1.5 4.5l1.409 1.409"
                      />
                    </svg>
                    <p class="text-sm">No snapshot URL configured</p>
                  </div>
                  <%!-- Device is stopped --%>
                  <div
                    :if={@device.state == :stopped}
                    class="flex flex-col items-center text-yellow-500 dark:text-yellow-400"
                  >
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke-width="1.5"
                      stroke="currentColor"
                      class="w-10 h-10 mb-2"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        d="M14.25 9v6m-4.5 0V9M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
                      />
                    </svg>
                    <p class="text-sm font-medium">Device is stopped</p>
                    <p class="text-xs mt-1 text-gray-400 dark:text-gray-500">
                      Start the device to view snapshots
                    </p>
                  </div>
                  <%!-- Device connection failed --%>
                  <div
                    :if={@device.state == :failed}
                    class="flex flex-col items-center text-red-500 dark:text-red-400"
                  >
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke-width="1.5"
                      stroke="currentColor"
                      class="w-10 h-10 mb-2"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z"
                      />
                    </svg>
                    <p class="text-sm font-medium">Device connection failed</p>
                    <p class="text-xs mt-1 text-gray-400 dark:text-gray-500">
                      Check device settings and connectivity
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </:tab_content>
        
    <!-- recordings tab -->
        <:tab_content for="recordings">
          <.live_component
            module={RecordingsListTab}
            id="recordings_list_tab"
            device={@device}
            params={@params}
          />
        </:tab_content>
        
    <!-- stats tab-->
        <:tab_content for="stats">
          <.live_component
            id="stats_tab"
            module={StatsTab}
            device={@device}
            main_stream_stats={@main_stream_stats}
            sub_stream_stats={@sub_stream_stats}
          />
        </:tab_content>

        <:tab_content for="settings">
          <.live_component
            id="settings_tab"
            module={SettingsTab}
            device={@device}
            current_user={@current_user}
          />
        </:tab_content>
        
    <!-- events tab-->
        <:tab_content for="events">
          <.live_component
            id="events_list_tab"
            module={EventsListTab}
            device={@device}
            params={@params}
          />
        </:tab_content>

        <:tab_content for="triggers">
          <.live_component
            id="triggers_tab"
            module={TriggersTab}
            device={@device}
          />
        </:tab_content>
      </.tabs>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => device_id} = params, _session, socket) do
    device = Devices.get!(device_id)

    active_tab = params["tab"] || "details"

    snapshot_enabled =
      not is_nil(device.stream_config.snapshot_uri) and Device.streaming?(device)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(ExNVR.PubSub, "device:#{device.id}")
      if snapshot_enabled, do: send(self(), :refresh_snapshot)
    end

    {:ok,
     assign(socket,
       device: device,
       active_tab: active_tab,
       main_stream_stats: nil,
       sub_stream_stats: nil,
       snapshot_enabled: snapshot_enabled,
       snapshot_data: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    active_tab = params["tab"] || socket.assigns.active_tab

    stats_topic = "stats:#{socket.assigns.device.id}"

    if active_tab == "stats",
      do: Phoenix.PubSub.subscribe(ExNVR.PubSub, stats_topic),
      else: Phoenix.PubSub.unsubscribe(ExNVR.PubSub, stats_topic)

    {:noreply,
     socket
     |> assign(:active_tab, active_tab)
     |> assign(:params, params)}
  end

  @impl true
  def handle_event("start-recording", _params, socket) do
    update_device_state(socket, :recording)
  end

  @impl true
  def handle_event("stop-recording", _params, socket) do
    update_device_state(socket, :stopped)
  end

  @impl true
  def handle_info({:tab_changed, %{tab: tab}}, socket) do
    params =
      socket.assigns.params
      |> Map.put("tab", tab)
      |> Map.put("filter_params", %{})
      |> Map.drop(["order_by", "order_direction"])

    {:noreply,
     socket
     |> assign(:active_tab, tab)
     |> assign(:params, params)
     |> push_patch(
       to: Routes.device_details_path(socket, :show, socket.assigns.device.id, params)
     )}
  end

  @impl true
  def handle_info(:refresh_snapshot, socket) do
    if socket.assigns.snapshot_enabled do
      Process.send_after(self(), :refresh_snapshot, @snapshot_refresh_interval)

      socket =
        case Devices.fetch_snapshot(socket.assigns.device) do
          {:ok, binary} ->
            assign(socket, :snapshot_data, "data:image/jpeg;base64,#{Base.encode64(binary)}")

          {:error, _reason} ->
            socket
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:device_updated, device}, socket) do
    was_snapshot_enabled = socket.assigns.snapshot_enabled

    snapshot_enabled =
      not is_nil(device.stream_config.snapshot_uri) and Device.streaming?(device)

    if snapshot_enabled and not was_snapshot_enabled do
      send(self(), :refresh_snapshot)
    end

    socket =
      socket
      |> assign(:device, device)
      |> assign(:snapshot_enabled, snapshot_enabled)

    case snapshot_enabled do
      true -> {:noreply, socket}
      false -> {:noreply, assign(socket, :snapshot_data, nil)}
    end
  end

  @impl true
  def handle_info({:video_stats, {:high, stats}}, socket) do
    {:noreply, assign(socket, :main_stream_stats, stats)}
  end

  @impl true
  def handle_info({:video_stats, {:low, stats}}, socket) do
    {:noreply, assign(socket, :sub_stream_stats, stats)}
  end

  def update_params(tab, id) do
    send_update(tab, id: id, params: %{})
  end

  defp update_device_state(socket, new_state) do
    user = socket.assigns.current_user
    device = socket.assigns.device

    with :ok <- authorize(user, :device, :update),
         {:ok, updated_device} <- Devices.update_state(device, new_state) do
      {:noreply, assign(socket, :device, updated_device)}
    else
      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to perform this action")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update device state")}
    end
  end
end
