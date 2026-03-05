defmodule ExNVRWeb.DeviceTabs.StatsTab do
  use ExNVRWeb, :live_component

  import ExNVRWeb.ViewUtils

  alias ExNVR.Model.Device

  @moduledoc false

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div :if={Device.streaming?(@device)} class="space-y-8">
        <div :if={!@main_stream_stats} role="status" class="flex items-center justify-center py-12">
          <svg
            aria-hidden="true"
            class="w-8 h-8 text-blue-200 animate-spin fill-blue-500"
            viewBox="0 0 100 101"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
          >
            <path
              d="M100 50.5908C100 78.2051 77.6142 100.591 50 100.591C22.3858 100.591 0 78.2051 0 50.5908C0 22.9766 22.3858 0.59082 50 0.59082C77.6142 0.59082 100 22.9766 100 50.5908ZM9.08144 50.5908C9.08144 73.1895 27.4013 91.5094 50 91.5094C72.5987 91.5094 90.9186 73.1895 90.9186 50.5908C90.9186 27.9921 72.5987 9.67226 50 9.67226C27.4013 9.67226 9.08144 27.9921 9.08144 50.5908Z"
              fill="currentColor"
            />
            <path
              d="M93.9676 39.0409C96.393 38.4038 97.8624 35.9116 97.0079 33.5539C95.2932 28.8227 92.871 24.3692 89.8167 20.348C85.8452 15.1192 80.8826 10.7238 75.2124 7.41289C69.5422 4.10194 63.2754 1.94025 56.7698 1.05124C51.7666 0.367541 46.6976 0.446843 41.7345 1.27873C39.2613 1.69328 37.813 4.19778 38.4501 6.62326C39.0873 9.04874 41.5694 10.4717 44.0505 10.1071C47.8511 9.54855 51.7191 9.52689 55.5402 10.0491C60.8642 10.7766 65.9928 12.5457 70.6331 15.2552C75.2735 17.9648 79.3347 21.5619 82.5849 25.841C84.9175 28.9121 86.7997 32.2913 88.1811 35.8758C89.083 38.2158 91.5421 39.6781 93.9676 39.0409Z"
              fill="currentFill"
            />
          </svg>
        </div>

        <.stream_section :if={@main_stream_stats} stats={@main_stream_stats} label="Main Stream" badge="PRIMARY" />
        <.stream_section :if={@sub_stream_stats} stats={@sub_stream_stats} label="Sub Stream" badge="SECONDARY" />
      </div>

      <div
        :if={!Device.streaming?(@device)}
        class="flex items-center justify-center py-24"
      >
        <div class="text-center p-8 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl shadow-sm">
          <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-2">Device Not Live</h2>
          <p class="text-gray-500 dark:text-gray-400">The device is not currently recording.</p>
        </div>
      </div>
    </div>
    """
  end

  attr :stats, :map, required: true
  attr :label, :string, required: true
  attr :badge, :string, required: true

  defp stream_section(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between gap-3 mb-4">
        <div class="flex items-center gap-3">
          <h2 class="text-xl font-bold text-gray-900 dark:text-white">{@label}</h2>
          <span class="px-3 py-1 bg-cyan-500 dark:bg-cyan-600 text-white text-xs font-semibold rounded-full">
            {@badge}
          </span>
        </div>
        <div class="flex items-center gap-3">
          <div class="flex items-center gap-1.5">
            <div class="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
            <span class="text-sm font-semibold text-green-500">STREAMING</span>
          </div>
          <span class="text-gray-300 dark:text-gray-600">|</span>
          <div class="flex items-center gap-1.5">
            <span class="text-sm text-gray-500 dark:text-gray-400">Codec:</span>
            <span class="text-sm font-semibold text-cyan-600 dark:text-cyan-400">{@stats.codec}</span>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <%!-- Resolution: arrows-pointing-out (expand corners) conveys dimensions --%>
        <.stat_card label="Resolution">
          <:icon>
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4"
              />
            </svg>
          </:icon>
          {elem(@stats.resolution, 0)}x{elem(@stats.resolution, 1)}
        </.stat_card>

        <%!-- Frame Rate: film/camera icon --%>
        <.stat_card label="Avg Frame Rate">
          <:icon>
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z"
              />
            </svg>
          </:icon>
          {:erlang.float_to_binary(@stats.avg_fps * 1.0, [{:decimals, 2}, :compact])}
        </.stat_card>

        <%!-- Bitrate: signal/activity icon --%>
        <.stat_card label="Avg Bitrate">
          <:icon>
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 19V6l2 5h6l-5 6-1-4H9z"
              />
            </svg>
          </:icon>
          {humanize_bitrate(@stats.avg_bitrate)}
        </.stat_card>

        <%!-- Total Frames: stack of layers --%>
        <.stat_card label="Total Frames">
          <:icon>
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
              />
            </svg>
          </:icon>
          {@stats.total_frames}
        </.stat_card>

        <%!-- GOP Size: repeat/cycle icon --%>
        <.stat_card label="GOP Size" subtitle={"Avg: #{@stats.avg_gop_size}"}>
          <:icon>
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
              />
            </svg>
          </:icon>
          {@stats.gop_size}
        </.stat_card>

        <%!-- Total Data: database/storage icon --%>
        <.stat_card label="Total Data">
          <:icon>
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4"
              />
            </svg>
          </:icon>
          {humanize_size(@stats.total_bytes)}
        </.stat_card>

        <%!-- Profile: tag/badge icon --%>
        <.stat_card label="Profile" subtitle={@stats.profile}>
          <:icon>
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z"
              />
            </svg>
          </:icon>
          MAIN
        </.stat_card>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :subtitle, :string, default: nil
  slot :icon, required: true
  slot :inner_block, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-4 shadow-sm flex flex-col gap-2">
      <div class="flex items-center gap-2">
        <div class="flex items-center justify-center w-6 h-6 rounded-md bg-gray-100 dark:bg-gray-700 text-gray-500 dark:text-gray-400 shrink-0">
          {render_slot(@icon)}
        </div>
        <span class="text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wider leading-none">
          {@label}
        </span>
      </div>
      <div>
        <div class="text-xl font-bold text-gray-900 dark:text-white leading-tight">
          {render_slot(@inner_block)}
        </div>
        <div :if={@subtitle} class="text-xs text-gray-500 dark:text-gray-400 mt-0.5">{@subtitle}</div>
      </div>
    </div>
    """
  end
end
