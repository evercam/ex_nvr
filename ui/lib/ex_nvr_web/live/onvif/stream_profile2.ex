defmodule ExNVRWeb.Onvif.StreamProfile2 do
  @moduledoc false

  use Phoenix.Component

  import ExNVRWeb.CoreComponents

  alias ExNVR.Devices.Cameras.StreamProfile
  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :profile, StreamProfile, required: true

  def stream_profile(assigns) do
    ~H"""
    <div class="p-5 border rounded-lg bg-white dark:border-gray-600 dark:bg-gray-950 dark:text-white">
      <div class="p-5">
        <h3 class="font-bold flex items-center gap-1">
          <.icon name="hero-camera" class="w-4 h-4 bg-blue-500" />{@profile.name}
        </h3>
      </div>
      <div class="p-5 pt-0 space-y-2 text-sm">
        <h4 class="font-semibold dark:text-gray-700">Video Settings</h4>
        <.separator />
        <div class="flex justify-between">
          <span class="dark:text-gray-600">Resolution:</span>
          <span class="font-mono">
            {@profile.video_config.width}x{@profile.video_config.height}
          </span>
        </div>
        <div class="flex justify-between">
          <span class="dark:text-gray-600">Codec:</span>
          <.tag>{codec(@profile.video_config.codec)}</.tag>
        </div>
        <div class="flex justify-between">
          <span class="dark:text-gray-600">Frame Rate:</span>
          <span class="font-mono">{@profile.video_config.frame_rate} fps</span>
        </div>
        <div class="flex justify-between">
          <span class="dark:text-gray-600">Bitrate:</span>
          <span class="font-mono">{@profile.video_config.bitrate} kbps</span>
        </div>
        <div class="flex justify-between">
          <span class="dark:text-gray-600">Bitrate Mode:</span>
          <.tag>{bitrate_mode(@profile.video_config.bitrate_mode)}</.tag>
        </div>
        <h4 class="font-semibold dark:text-gray-700">Stream URLs</h4>
        <.separator />
        <div class="space-y-2">
          <div class="flex justify-between">
            <span class="dark:text-gray-600 flex items-center gap-1">
              <.icon name="hero-link" class="w-3 h-3" />Stream URI
            </span>
            <button
              phx-click={JS.dispatch("events:clipboard-copy", to: "##{@id}-stream-uri")}
              class="inline-flex items-center justify-center gap-2 whitespace-nowrap text-xs hover:bg-gray-600 px-2 rounded"
            >
              Copy
            </button>
          </div>
          <div
            id={"#{@id}-stream-uri"}
            class="text-xs font-mono bg-gray-100 dark:bg-gray-800 p-2 rounded break-all"
          >
            {@profile.stream_uri}
          </div>
        </div>
        <div class="space-y-2">
          <div class="flex justify-between">
            <span class="dark:text-gray-600 flex items-center gap-1">
              <.icon name="hero-photo" class="w-3 h-3" />Snapshot URI
            </span>
            <button
              phx-click={JS.dispatch("events:clipboard-copy", to: "##{@id}-snapshot-uri")}
              class="inline-flex items-center justify-center gap-2 whitespace-nowrap text-xs hover:bg-gray-600 px-2 rounded"
            >
              Copy
            </button>
          </div>
          <div
            id={"#{@id}-snapshot-uri"}
            class="text-xs font-mono bg-gray-100 dark:bg-gray-800 p-2 rounded break-all"
          >
            {@profile.snapshot_uri}
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp bitrate_mode(:vbr), do: "Variable"
  defp bitrate_mode(:cbr), do: "Constant"
  defp bitrate_mode(other), do: other

  defp codec(:h264), do: "H.264"
  defp codec(:h265), do: "H.265"
  defp codec(:jpeg), do: "MJPEG"
  defp codec(other), do: other
end
