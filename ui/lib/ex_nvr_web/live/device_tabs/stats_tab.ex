defmodule ExNVRWeb.DeviceTabs.StatsTab do
  use ExNVRWeb, :live_component

  alias ExNVR.Model.Device

  @moduledoc false

  def render(assigns) do
    if assigns.device.state == :recording do
      ~H"""
      <div class="bg-gray-100 dark:bg-gray-900 min-h-screen p-8 font-sans">
        <div class="bg-white dark:bg-gray-800 rounded-xl shadow-lg p-6 md:p-10 mx-auto max-w-6xl">
          <div class="flex flex-col md:flex-row gap-8 md:gap-20 justify-between">
            <div class="flex-1 space-y-6">
              <div class="flex items-center gap-2">
                <h3 class="text-xl font-bold text-gray-700 dark:text-gray-300">Main Stream</h3>
              </div>
              <div class="space-y-4 text-sm">
                <div
                  :for={{title, stats} <- @main_stream_stats}
                  class="flex justify-between items-center pb-2 border-b border-gray-200 dark:border-gray-700"
                >
                  <span class="text-gray-600 dark:text-gray-400 font-semibold">{title}</span>
                  <span class="text-gray-900 dark:text-white font-medium">{stats}</span>
                </div>
              </div>
              <div>
                <.vue v-component="StatsView" class="h-80 flex justify-center" url={@main_stream_url} />
              </div>
            </div>
            <div :if={Device.has_sub_stream(@device)} class="flex-1 space-y-6">
              <div class="flex items-center gap-2">
                <h3 class="text-xl font-bold text-gray-700 dark:text-gray-300">Sub Stream</h3>
              </div>
              <div class="space-y-4 text-sm">
                <div
                  :for={{title, stats} <- @sub_stream_stats}
                  class="flex justify-between items-center pb-2 border-b border-gray-200 dark:border-gray-700"
                >
                  <span class="text-gray-600 dark:text-gray-400 font-semibold">{title}</span>
                  <span class="text-gray-900 dark:text-white font-medium">{stats}</span>
                </div>
              </div>
              <div>
                <.vue v-component="StatsView" class="h-80" url={@sub_stream_url} />
              </div>
            </div>
          </div>
        </div>
      </div>
      """
    else
      ~H"""
      <div class="flex items-center justify-center min-h-screen bg-gray-100 dark:bg-gray-900">
        <div class="text-center p-8 bg-white dark:bg-gray-800 rounded-lg shadow-lg">
          <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Device Not Live</h2>
          <p class="text-gray-600 dark:text-gray-400">The device is not currently recording.</p>
        </div>
      </div>
      """
    end
  end

  def mount(socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    {main_stream_url, sub_stream_url} = stream_url(assigns.device, nil)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:main_stream_url, main_stream_url)
     |> assign(:sub_stream_url, sub_stream_url)}
  end

  @spec stream_url(map(), String.t()) :: {String.t(), String.t()}
  defp stream_url(device, datetime) do
    main_stream_url =
      ~p"/api/devices/#{device.id}/hls/index.m3u8?#{%{pos: format_date(datetime), stream: "high"}}"

    sub_stream_url =
      ~p"/api/devices/#{device.id}/hls/index.m3u8?#{%{pos: format_date(datetime), stream: "low"}}"

    {main_stream_url, sub_stream_url}
  end

  defp format_date(nil), do: nil
  defp format_date(datetime), do: DateTime.to_iso8601(datetime)
end
