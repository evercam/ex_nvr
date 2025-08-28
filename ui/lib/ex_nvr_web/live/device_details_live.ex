defmodule ExNVRWeb.DeviceDetailsLive do
  use ExNVRWeb, :live_view

  require Logger

  alias ExNVR.Devices
  alias ExNVRWeb.DeviceTabs.{EventsListTab, RecordingsListTab, StatsTab}
  alias ExNVRWeb.Router.Helpers, as: Routes

  import ExNVRWeb.ViewUtils

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
          <div class="text-center text-gray-500 dark:text-gray-400">
            settings tab coming soon...
          </div>
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
      </.tabs>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => device_id} = params, _session, socket) do
    device = Devices.get!(device_id)

    active_tab = params["tab"] || "details"

    {:ok,
     assign(socket,
       device: device,
       active_tab: active_tab,
       main_stream_stats: %{},
       sub_stream_stats: %{}
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
    if tab == "stats" do
      Phoenix.PubSub.subscribe(ExNVR.PubSub, "stream_info")
    else
      Phoenix.PubSub.unsubscribe(ExNVR.PubSub, "stream_info")
    end

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
  def handle_info({:main_stream, message}, socket) do
    {:noreply, assign(socket, main_stream_stats: format_stats(message))}
  end

  @impl true
  def handle_info({:sub_stream, message}, socket) do
    {:noreply, assign(socket, sub_stream_stats: format_stats(message))}
  end

  @spec format_stats(map()) :: map()
  def format_stats(stats) do
    %{
      "Resolution" => "#{stats["height"]}x#{stats["width"]}",
      "R-Frame Rate" => "#{stats["r_frame_rate"]}",
      "AVG-Frame Rate" => "#{stats["avg_frame_rate"]}",
      "Color Primaries" => stats["color_primaries"],
      "color_transfer" => stats["color_transfer"],
      "Bits Per Raw Sample" => stats["bits_per_raw_sample"],
      "Codec Long Name" => stats["codec_long_name"],
      "Codec Type" => stats["codec_type"],
      "AVG Frame Rate" => stats["avg_frame_rate"],
      "Bit Rate" => humanize_bitrate(String.to_integer(stats["bit_rate"]))
    }
  end

  def update_params(tab, id) do
    send_update(tab, id: id, params: %{})
  end
end
