defmodule ExNVRWeb.SchedulerComponent do
  @moduledoc """
  Scheduler component for programming repetitive events and cronjobs.
  """

  use Phoenix.LiveComponent

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="scheduler-wrapper"
      class="flex flex-col items-center justify-center p-4"
    >
      <div class="overflow-x-auto w-full">
        <!-- Schedule grid -->
        <div id="scheduler-grid" phx-hook="Scheduler" class="grid grid-cols-8 text-sm">
          <!-- Header -->
          <div class="bg-blue-500 text-black dark:bg-gray-400 dark:text-white font-bold p-2 border border-black dark:border-white">Time/Day</div>
          <%= for day <- ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] do %>
            <div class="bg-blue-400 text-black dark:bg-gray-500 dark:text-white font-bold p-2 border border-black dark:border-white"><%= day %></div>
          <% end %>

          <!-- Times and Days -->
          <%= for hour <- 0..24//2 do %>
            <div class="p-2 border border-black dark:border-white bg-blue-400 text-black dark:bg-gray-500 dark:text-white font-bold"> <%= hour %>:00 </div>
            <%= for _day <- 1..7 do %>
              <div class="p-2 border border-black dark:border-white schedule-block hover:bg-sky-500"></div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
