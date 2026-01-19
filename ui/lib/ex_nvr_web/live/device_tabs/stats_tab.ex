defmodule ExNVRWeb.DeviceTabs.StatsTab do
  use ExNVRWeb, :live_component

  import ExNVRWeb.ViewUtils

  @moduledoc false

  @impl true
  def render(assigns) do
    if assigns.device.state == :recording do
      ~H"""
      <div class="bg-gray-50 dark:bg-slate-900 text-gray-900 dark:text-gray-100 p-8 font-sans">
        
      <!-- Main Stream Section -->
        <div :if={@main_stream_stats} class="mb-8 ">
          <div class="flex items-center justify-between gap-3 mb-4">
            <div class="flex gap-3">
              <h2 class="text-xl font-bold dark:text-white">Main Stream</h2>
              <span class="px-3 py-1 bg-cyan-500 dark:bg-cyan-600 text-white dark:text-cyan-100 text-xs font-semibold rounded-full">
                PRIMARY
              </span>
            </div>

            <div>
              <div class="flex items-center gap-2">
                <div class="flex items-center gap-2">
                  <div class="w-3 h-3 bg-green-500 rounded-full animate-pulse"></div>
                  <span class="text-green-500 font-semibold">STREAMING</span>
                </div>
                <div class="flex items-center gap-2">
                  <span class="text-gray-600 dark:text-gray-400">Codec:</span>
                  <span class="text-cyan-600 dark:text-cyan-400 font-semibold">
                    {@main_stream_stats.codec}
                  </span>
                </div>
              </div>
            </div>
          </div>
          
      <!-- Main Stream Cards -->
          <div class="flex flex-wrap gap-4 mb-6">
            <!-- Resolution Card -->
            <div class="flex-1 min-w-[240px] bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-lg p-5">
              <div class="flex items-center justify-between mb-2">
                <div class="text-gray-600 dark:text-gray-400 text-sm uppercase">Resolution</div>
                <svg
                  class="w-5 h-5 text-gray-400 dark:text-gray-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <rect x="3" y="3" width="18" height="18" rx="2" stroke-width="2" />
                </svg>
              </div>
              <div class="text-3xl font-bold text-gray-900 dark:text-white mb-1">
                {elem(@main_stream_stats.resolution, 0)}x{elem(@main_stream_stats.resolution, 1)}
              </div>
            </div>
            
      <!-- Frame Rate Card -->
            <div class="flex-1 min-w-[240px] bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-lg p-5">
              <div class="flex items-center justify-between mb-2">
                <div class="text-gray-600 dark:text-gray-400 text-sm uppercase">Frame Rate</div>
                <svg
                  class="w-5 h-5 text-gray-400 dark:text-gray-500"
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
              <div class="text-3xl font-bold text-gray-900 dark:text-white mb-1">
                {floor(@main_stream_stats.avg_fps)}
              </div>
              <div class="text-gray-500 dark:text-gray-400 text-sm">Average</div>
            </div>
            
      <!-- Bitrate Card -->
            <div class="flex-1 min-w-[240px] bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-lg p-5">
              <div class="flex items-center justify-between mb-2">
                <div class="text-gray-600 dark:text-gray-400 text-sm uppercase">Bitrate</div>
                <svg
                  class="w-5 h-5 text-gray-400 dark:text-gray-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M13 10V3L4 14h7v7l9-11h-7z"
                  />
                </svg>
              </div>
              <div class="text-3xl font-bold text-gray-900 dark:text-white mb-1">
                {humanize_bitrate(@main_stream_stats.avg_bitrate)}
              </div>
              <div class="text-gray-500 dark:text-gray-400 text-sm">Average</div>
            </div>
            
      <!-- Total Frames Card -->
            <div class="flex-1 min-w-[240px] bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-lg p-5">
              <div class="flex items-center justify-between mb-2">
                <div class="text-gray-600 dark:text-gray-400 text-sm uppercase">Total Frames</div>
                <svg
                  class="w-5 h-5 text-gray-400 dark:text-gray-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4"
                  />
                </svg>
              </div>
              <div class="text-3xl font-bold text-gray-900 dark:text-white">
                {@main_stream_stats.total_frames}
              </div>
            </div>
          </div>
          
      <!-- Additional Main Stream Cards -->
          <div class="flex flex-wrap gap-4">
            <!-- GOP Size Card -->
            <div class="flex-1 min-w-[240px] bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-lg p-5">
              <div class="flex items-center justify-between mb-2">
                <div class="text-gray-600 dark:text-gray-400 text-sm uppercase">GOP Size</div>
                <svg
                  class="w-5 h-5 text-gray-400 dark:text-gray-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M13 10V3L4 14h7v7l9-11h-7z"
                  />
                </svg>
              </div>
              <div class="text-3xl font-bold text-gray-900 dark:text-white mb-1">
                {@main_stream_stats.gop_size}
              </div>
              <div class="text-gray-500 dark:text-gray-400 text-sm">
                Avg: {@main_stream_stats.avg_gop_size}
              </div>
            </div>
            
      <!-- Keyframe Distance Card -->
            <div class="flex-1 min-w-[240px] bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-lg p-5">
              <div class="flex items-center justify-between mb-2">
                <div class="text-gray-600 dark:text-gray-400 text-sm uppercase">Keyframe Distance</div>
                <svg
                  class="w-5 h-5 text-gray-400 dark:text-gray-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <circle cx="12" cy="12" r="10" stroke-width="2" />
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6l4 2" />
                </svg>
              </div>
              <div class="text-3xl font-bold text-gray-900 dark:text-white mb-1">
                {@main_stream_stats.frames_since_last_keyframe}
              </div>
              <div class="text-gray-500 dark:text-gray-400 text-sm">Frames since last</div>
            </div>
            
      <!-- Total Data Card -->
            <div class="flex-1 min-w-[240px] bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-lg p-5">
              <div class="flex items-center justify-between mb-2">
                <div class="text-gray-600 dark:text-gray-400 text-sm uppercase">Total Data</div>
                <svg
                  class="w-5 h-5 text-gray-400 dark:text-gray-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4"
                  />
                </svg>
              </div>
              <div class="text-3xl font-bold text-gray-900 dark:text-white">
                {humanize_size(@main_stream_stats.total_bytes)}
              </div>
            </div>
            
      <!-- Profile Card -->
            <div class="flex-1 min-w-[240px] bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-lg p-5">
              <div class="flex items-center justify-between mb-2">
                <div class="text-gray-600 dark:text-gray-400 text-sm uppercase">Profile</div>
                <svg
                  class="w-5 h-5 text-gray-400 dark:text-gray-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
                  />
                </svg>
              </div>
              <div class="text-3xl font-bold text-gray-900 dark:text-white mb-1">MAIN</div>
              <div class="text-gray-500 dark:text-gray-400 text-sm">{@main_stream_stats.profile}</div>
            </div>
          </div>
        </div>

        <div :if={!@main_stream_stats} role="status" class="flex items-center justify-center ">
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
        
      <!-- Sub Stream Section -->
        <div :if={@sub_stream_stats} class="mb-8">
          <div class="flex items-center justify-between gap-3 mb-4">
            <div class="flex gap-3">
              <h2 class="text-xl font-bold dark:text-white">Sub Stream</h2>
              <span class="px-3 py-1 bg-cyan-500 dark:bg-cyan-600 text-white dark:text-cyan-100 text-xs font-semibold rounded-full">
                Secondary
              </span>
            </div>

            <div>
              <div class="flex items-center gap-2">
                <div class="flex items-center gap-2">
                  <div class="w-3 h-3 bg-green-500 rounded-full animate-pulse"></div>
                  <span class="text-green-500 font-semibold">STREAMING</span>
                </div>
                <div class="flex items-center gap-2">
                  <span class="text-gray-600 dark:text-gray-400">Codec:</span>
                  <span class="text-cyan-600 dark:text-cyan-400 font-semibold">
                    {@sub_stream_stats.codec}
                  </span>
                </div>
              </div>
            </div>
          </div>
          
      <!-- Main Stream Cards -->
          <div class="flex flex-wrap gap-4 mb-6">
            <!-- Resolution Card -->
            <div class="flex-1 min-w-[240px] bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-lg p-5">
              <div class="flex items-center justify-between mb-2">
                <div class="text-gray-600 dark:text-gray-400 text-sm uppercase">Resolution</div>
                <svg
                  class="w-5 h-5 text-gray-400 dark:text-gray-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <rect x="3" y="3" width="18" height="18" rx="2" stroke-width="2" />
                </svg>
              </div>
              <div class="text-3xl font-bold text-gray-900 dark:text-white mb-1">
                {elem(@sub_stream_stats.resolution, 0)}x{elem(@sub_stream_stats.resolution, 1)}
              </div>
            </div>
            
      <!-- Frame Rate Card -->
            <div class="flex-1 min-w-[240px] bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-lg p-5">
              <div class="flex items-center justify-between mb-2">
                <div class="text-gray-600 dark:text-gray-400 text-sm uppercase">Frame Rate</div>
                <svg
                  class="w-5 h-5 text-gray-400 dark:text-gray-500"
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
              <div class="text-3xl font-bold text-gray-900 dark:text-white mb-1">
                {floor(@sub_stream_stats.avg_fps)}
              </div>
              <div class="text-gray-500 dark:text-gray-400 text-sm">Average</div>
            </div>
            
      <!-- Bitrate Card -->
            <div class="flex-1 min-w-[240px] bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-lg p-5">
              <div class="flex items-center justify-between mb-2">
                <div class="text-gray-600 dark:text-gray-400 text-sm uppercase">Bitrate</div>
                <svg
                  class="w-5 h-5 text-gray-400 dark:text-gray-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M13 10V3L4 14h7v7l9-11h-7z"
                  />
                </svg>
              </div>
              <div class="text-3xl font-bold text-gray-900 dark:text-white mb-1">
                {humanize_bitrate(@sub_stream_stats.avg_bitrate)}
              </div>
              <div class="text-gray-500 dark:text-gray-400 text-sm">Average</div>
            </div>
            
      <!-- Total Frames Card -->
            <div class="flex-1 min-w-[240px] bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-lg p-5">
              <div class="flex items-center justify-between mb-2">
                <div class="text-gray-600 dark:text-gray-400 text-sm uppercase">Total Frames</div>
                <svg
                  class="w-5 h-5 text-gray-400 dark:text-gray-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4"
                  />
                </svg>
              </div>
              <div class="text-3xl font-bold text-gray-900 dark:text-white">
                {@sub_stream_stats.total_frames}
              </div>
            </div>
          </div>
          
      <!-- Additional Main Stream Cards -->
          <div class="flex flex-wrap gap-4">
            <!-- GOP Size Card -->
            <div class="flex-1 min-w-[240px] bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-lg p-5">
              <div class="flex items-center justify-between mb-2">
                <div class="text-gray-600 dark:text-gray-400 text-sm uppercase">GOP Size</div>
                <svg
                  class="w-5 h-5 text-gray-400 dark:text-gray-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M13 10V3L4 14h7v7l9-11h-7z"
                  />
                </svg>
              </div>
              <div class="text-3xl font-bold text-gray-900 dark:text-white mb-1">
                {@sub_stream_stats.gop_size}
              </div>
              <div class="text-gray-500 dark:text-gray-400 text-sm">
                Avg: {@sub_stream_stats.avg_gop_size}
              </div>
            </div>
            
      <!-- Keyframe Distance Card -->
            <div class="flex-1 min-w-[240px] bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-lg p-5">
              <div class="flex items-center justify-between mb-2">
                <div class="text-gray-600 dark:text-gray-400 text-sm uppercase">Keyframe Distance</div>
                <svg
                  class="w-5 h-5 text-gray-400 dark:text-gray-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <circle cx="12" cy="12" r="10" stroke-width="2" />
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6l4 2" />
                </svg>
              </div>
              <div class="text-3xl font-bold text-gray-900 dark:text-white mb-1">
                {@sub_stream_stats.frames_since_last_keyframe}
              </div>
              <div class="text-gray-500 dark:text-gray-400 text-sm">Frames since last</div>
            </div>
            
      <!-- Total Data Card -->
            <div class="flex-1 min-w-[240px] bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-lg p-5">
              <div class="flex items-center justify-between mb-2">
                <div class="text-gray-600 dark:text-gray-400 text-sm uppercase">Total Data</div>
                <svg
                  class="w-5 h-5 text-gray-400 dark:text-gray-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4"
                  />
                </svg>
              </div>
              <div class="text-3xl font-bold text-gray-900 dark:text-white">
                {humanize_size(@sub_stream_stats.total_bytes)}
              </div>
            </div>
            
      <!-- Profile Card -->
            <div class="flex-1 min-w-[240px] bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-lg p-5">
              <div class="flex items-center justify-between mb-2">
                <div class="text-gray-600 dark:text-gray-400 text-sm uppercase">Profile</div>
                <svg
                  class="w-5 h-5 text-gray-400 dark:text-gray-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
                  />
                </svg>
              </div>
              <div class="text-3xl font-bold text-gray-900 dark:text-white mb-1">MAIN</div>
              <div class="text-gray-500 dark:text-gray-400 text-sm">{@sub_stream_stats.profile}</div>
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

  defp format_date(nil), do: nil
  defp format_date(datetime), do: DateTime.to_iso8601(datetime)
end
