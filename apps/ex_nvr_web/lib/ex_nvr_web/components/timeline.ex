defmodule ExNVRWeb.TimelineComponent do
  @moduledoc """
  Timeline component for the video player that shows all dates
  where recordings are available.

  Once clicked down, an event `datetime` with the date value is sent. The
  live view should handle this event accordingly in `handle_event/3` callback.
  """

  use Phoenix.LiveComponent

  @impl true
  def render(assigns) do
    ~H"""
    <div id="timeline-wrapper" phx-hook="Timeline" class="relative">
      <div
        id="timeline"
        class="relative bg-gray-900 h-11 rounded-br rounded-bl overflow-hidden select-none"
        data-segments={@segments}
        data-timezone={@timezone}
      >
      </div>
      <div
        id="tooltip"
        class="hidden absolute bg-gray-900 text-white border border-gray-700 rounded px-2"
      >
      </div>
      <div id="cursor" class="hidden absolute bg-red-600 w-px h-full top-0 pointer-events-none"></div>
    </div>
    """
  end
end
