defmodule ExNVRWeb.TimelineComponent do
  use Phoenix.Component
  import Jason

  def timeline(assigns) do
    ~H"""
    <div id="timeline-wrapper" phx-hook="Timeline" class="relative">
      <div
        id="timeline"
        class="relative bg-gray-900 h-11 rounded-br rounded-bl overflow-hidden select-none"
        data-segments={@segments}
      >
      </div>
      <div id="tooltip" class="hidden absolute bg-gray-900 text-white border border-gray-700 rounded px-2"></div>
      <div id="cursor" class="hidden absolute bg-gray-400 w-px h-full top-0 pointer-events-none"></div>
    </div>
    """
  end
end
