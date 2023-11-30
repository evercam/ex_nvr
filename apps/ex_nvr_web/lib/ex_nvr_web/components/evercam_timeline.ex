defmodule ExNVRWeb.VueTimelineComponent do
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
        id="vue-timeline-wrapper"
        phx-hook="VueTimeline"
        class="relative"
      >
        <div class="timeline"></div>
      </div>
    """
  end
end
