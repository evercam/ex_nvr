defmodule ExNVRWeb.DeviceTabs.StatsTab do
  use ExNVRWeb, :live_component

  alias ExNVR.Model.Device

  @moduledoc false

  @impl true
  def render(assigns) do
    if assigns.device.state == :recording do
      ~H"""
      <div class="max-w-7xl mx-auto bg-gray-50 dark:bg-[#0a0e1a] text-gray-900 dark:text-gray-100 p-6">
        
      <!-- Stream Cards -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
          
      <!-- Main Stream -->
          <div class="bg-white dark:bg-[#131824] border border-gray-200 dark:border-gray-800 rounded-xl overflow-hidden">
            <div class="p-6 border-b border-gray-200 dark:border-gray-800 flex items-center justify-between">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 bg-grey-500/20 rounded-lg flex items-center justify-center">
                  <svg
                    class="w-5 h-5 text-grey-500 dark:text-cyan-400"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z"
                    />
                  </svg>
                </div>
                <div>
                  <h3 class="text-lg font-semibold text-gray-900 dark:text-white">Main Stream</h3>
                  <p class="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wide">
                    Primary Stream
                  </p>
                </div>
              </div>
              <div class="flex items-center gap-2">
                <span class="w-2 h-2 bg-green-400 rounded-full animate-pulse"></span>
                <span class="text-sm text-green-500 dark:text-green-400 font-medium">Live</span>
              </div>
            </div>

            <div class="relative bg-gray-200 dark:bg-[#0f1419] aspect-video flex items-center justify-center group">
              <span class="absolute top-4 left-4 px-2 py-1 bg-green-500/20 text-green-600 dark:text-green-400 text-xs font-semibold rounded flex items-center gap-1">
                <span class="w-1.5 h-1.5 bg-green-400 rounded-full"></span> LIVE
              </span>
              <.vue v-component="StatsView" class="w-full h-full" url={@main_stream_url} />
              <span
                :if={@main_stream_stats != nil}
                class="absolute bottom-4 right-4 px-2 py-1 bg-black/60 text-cyan-400 text-xs font-mono"
              >
                {"#{elem(@main_stream_stats.resolution, 0)}×#{elem(@main_stream_stats.resolution, 1)}"}
              </span>
              <span class="absolute bottom-4 left-1/2 -translate-x-1/2 text-gray-500 dark:text-gray-400 text-sm uppercase tracking-wider">
                Live Snapshot
              </span>
            </div>
            
      <!-- Stats Grid -->
            <div
              :if={@main_stream_stats != nil}
              class="p-6 grid grid-cols-4 gap-4 border-b border-gray-200 dark:border-gray-800"
            >
              <div class="text-center">
                <div class="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-1">
                  Framerate
                </div>
                <div class="text-lg font-bold text-cyan-600 dark:text-cyan-400">
                  {Float.round(@main_stream_stats.avg_fps, 2)}
                  <span class="text-sm text-gray-500 dark:text-gray-400">fps</span>
                </div>
              </div>

              <div class="text-center">
                <div class="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-1">
                  Total Frames
                </div>
                <div class="text-lg font-bold text-cyan-600 dark:text-cyan-400">
                  {@main_stream_stats.total_frames}
                </div>
              </div>

              <div class="text-center">
                <div class="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-1">
                  Bitrate
                </div>
                <div class="text-lg font-bold text-cyan-600 dark:text-cyan-400">
                  {Float.round(@main_stream_stats.avg_bitrate / 1000, 1)}
                  <span class="text-sm text-gray-500 dark:text-gray-400">Kbps</span>
                </div>
              </div>
              <div class="text-center">
                <div class="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-1">
                  Total Size
                </div>
                <div class="text-lg font-bold text-cyan-600 dark:text-cyan-400">
                  {Float.round(@main_stream_stats.total_bytes / 1_048_576, 2)} MB
                </div>
              </div>
            </div>

            <div
              :if={@main_stream_stats == nil}
              role="status"
              class="p-6 flex justify-center items-center"
            >
              <svg
                aria-hidden="true"
                class="w-8 h-8 animate-spin text-gray-500 fill-blue-600"
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
            
      <!-- Codec & Details -->
            <div :if={@main_stream_stats != nil} class="p-6 flex justify-between text-sm">
              <div>
                <span class="text-gray-500 dark:text-gray-400 uppercase text-xs tracking-wide">
                  Codec
                </span>
                <div class="text-gray-900 dark:text-white font-mono mt-1">
                  {to_string(@main_stream_stats.codec)}
                </div>
              </div>
              <div>
                <span class="text-gray-500 dark:text-gray-400 uppercase text-xs tracking-wide">
                  Avg GOP Size
                </span>
                <div class="text-gray-900 dark:text-white font-mono mt-1">
                  {@main_stream_stats.gop_size}
                </div>
              </div>
              <div class="col-span-2">
                <span class="text-gray-500 dark:text-gray-400 uppercase text-xs tracking-wide">
                  Frames Since Last Keyframe
                </span>
                <div class="text-gray-900 dark:text-white font-mono mt-1">
                  {@main_stream_stats.frames_since_last_keyframe}
                </div>
              </div>
            </div>
            
      <!-- Additional Stream Info -->
            <div
              :if={@main_stream_stats != nil}
              class="p-6 border-t border-gray-200 dark:border-gray-800 space-y-3 text-sm"
            >
              <div class="flex justify-between">
                <span class="text-gray-500 dark:text-gray-400">Stream Quality</span><span class="text-gray-900 dark:text-white font-mono capitalize"><%= @main_stream_stats.stream %></span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-500 dark:text-gray-400">Profile</span><span class="text-gray-900 dark:text-white font-mono"><%= @main_stream_stats.profile |> Atom.to_string() |> String.capitalize() %></span>
              </div>
            </div>
          </div>
          
      <!-- Sub Stream -->
          <div class="bg-white dark:bg-[#131824] border border-gray-200 dark:border-gray-800 rounded-xl overflow-hidden">
            <div class="p-6 border-b border-gray-200 dark:border-gray-800 flex items-center justify-between">
              <div>
                <h3 class="text-lg font-semibold text-gray-900 dark:text-white">Sub Stream</h3>
                <p class="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wide">
                  Secondary Stream
                </p>
              </div>
              <div class="flex items-center gap-2">
                <span class="w-2 h-2 bg-green-400 rounded-full animate-pulse"></span>
                <span class="text-sm text-green-500 dark:text-green-400 font-medium">Live</span>
              </div>
            </div>

            <div class="relative bg-gray-200 dark:bg-[#0f1419] aspect-video flex items-center justify-center">
              <.vue v-component="StatsView" class="w-full h-full" url={@sub_stream_url} />
              <span
                :if={@sub_stream_stats != nil}
                class="absolute bottom-4 right-4 px-2 py-1 bg-black/60 text-amber-400 text-xs font-mono"
              >
                {"#{elem(@sub_stream_stats.resolution, 0)}×#{elem(@sub_stream_stats.resolution, 1)}"}
              </span>
              <span class="absolute bottom-4 left-1/2 -translate-x-1/2 text-gray-500 dark:text-gray-400 text-sm uppercase tracking-wider">
                Live Snapshot
              </span>
            </div>
            
      <!-- Stats Grid -->
            <div
              :if={@sub_stream_stats != nil}
              class="p-6 grid grid-cols-4 gap-4 border-b border-gray-200 dark:border-gray-800"
            >
              <div class="text-center">
                <div class="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-1">
                  Framerate
                </div>
                <div class="text-lg font-bold text-amber-500 dark:text-amber-400">
                  {Float.round(@sub_stream_stats.avg_fps, 2)}
                  <span class="text-sm text-gray-500 dark:text-gray-400">fps</span>
                </div>
              </div>

              <div class="text-center">
                <div class="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-1">
                  Total Frames
                </div>
                <div class="text-lg font-bold text-amber-500 dark:text-amber-400">
                  {@sub_stream_stats.total_frames}
                </div>
              </div>

              <div class="text-center">
                <div class="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-1">
                  Bitrate
                </div>
                <div class="text-lg font-bold text-amber-500 dark:text-amber-400">
                  {Float.round(@sub_stream_stats.avg_bitrate / 1000, 1)}
                  <span class="text-sm text-gray-500 dark:text-gray-400">Kbps</span>
                </div>
              </div>

              <div class="text-center">
                <div class="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-1">
                  Total Size
                </div>
                <div class="text-lg font-bold text-cyan-600 dark:text-cyan-400">
                  {Float.round(@sub_stream_stats.total_bytes / 1_048_576, 2)} MB
                </div>
              </div>
            </div>

            <div
              :if={@sub_stream_stats == nil}
              role="status"
              class="p-6 flex justify-center items-center"
            >
              <svg
                aria-hidden="true"
                class="w-8 h-8 animate-spin text-gray-500 fill-blue-600"
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
            
      <!-- Codec & Details -->

            <div :if={@sub_stream_stats != nil} class="p-6 flex justify-between text-sm">
              <div>
                <span class="text-gray-500 dark:text-gray-400 uppercase text-xs tracking-wide">
                  Codec
                </span>
                <div class="text-gray-900 dark:text-white font-mono mt-1">
                  {to_string(@sub_stream_stats.codec)}
                </div>
              </div>
              <div>
                <span class="text-gray-500 dark:text-gray-400 uppercase text-xs tracking-wide">
                  Avg GOP Size
                </span>
                <div class="text-gray-900 dark:text-white font-mono mt-1">
                  {@sub_stream_stats.gop_size}
                </div>
              </div>
              <div class="col-span-2">
                <span class="text-gray-500 dark:text-gray-400 uppercase text-xs tracking-wide">
                  Frames Since Last Keyframe
                </span>
                <div class="text-gray-900 dark:text-white font-mono mt-1">
                  {@sub_stream_stats.frames_since_last_keyframe}
                </div>
              </div>
            </div>
            
      <!-- Additional Stream Info -->
            <div
              :if={@sub_stream_stats != nil}
              class="p-6 border-t border-gray-200 dark:border-gray-800 space-y-3 text-sm"
            >
              <div class="flex justify-between">
                <span class="text-gray-500 dark:text-gray-400">Stream Quality</span><span class="text-gray-900 dark:text-white font-mono"><%= String.capitalize(to_string(@sub_stream_stats.stream)) %></span>
              </div>

              <div class="flex justify-between">
                <span class="text-gray-500 dark:text-gray-400">Profile</span><span class="text-gray-900 dark:text-white font-mono"><%= @sub_stream_stats.profile |> Atom.to_string() |> String.capitalize() %></span>
              </div>
            </div>
          </div>
        </div>
      </div>
      """
    else
      ~H"""
      <div class="flex items-center justify-center min-h-screen bg-gray-50 dark:bg-[#0a0e1a]">
        <div class="text-center p-8 bg-white dark:bg-[#131824] border border-gray-200 dark:border-gray-800 rounded-xl shadow-xl">
          <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Device Not Live</h2>
          <p class="text-gray-500 dark:text-gray-400">The device is not currently recording.</p>
        </div>
      </div>
      """
    end
  end

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
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
