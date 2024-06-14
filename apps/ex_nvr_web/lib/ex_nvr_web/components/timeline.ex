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
    <div
      id="timeline-wrapper"
      phx-hook="Timeline"
      class="relative"
      data-segments={@segments}
      data-timezone={@timezone}
    >
      <div id="background" class="bg-zinc-800 dark:bg-gray-900 w-full h-7 absolute top-0"></div>
      <div
        id="timeline"
        class="relative h-13 rounded-br rounded-bl select-none overflow-x-hidden text-gray-900"
        phx-update="ignore"
      >
      </div>
      <div
        id="tooltip"
        class="hidden absolute bg-gray-100 text-gray-700 dark:text-white dark:bg-gray-900 border dark:border-gray-700 rounded px-2"
      >
      </div>
      <div
        id="cursor"
        class="hidden absolute bg-red-800 dark:bg-red-600 w-px h-7 top-0 pointer-events-none"
      >
      </div>
    </div>
    """
  end
end
