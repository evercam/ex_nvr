defmodule ExNVRWeb.SchedulerComponent do
  @moduledoc """
  Scheduler component for programming repetitive events and cronjobs.
  """

  use Phoenix.LiveComponent
  import ExNVRWeb.CoreComponents

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
          <div class="bg-red-700 text-white dark:bg-gray-400 dark:text-white font-bold p-2 border border-black dark:border-white">Time/Day</div>
          <%= for day <- ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"] do %>
            <div class="bg-red-400 text-black dark:bg-gray-500 dark:text-white font-bold p-2 border border-black dark:border-white"><%= day %></div>
          <% end %>

          <!-- Times and Days -->
          <%= for hour <- 0..24//2 do %>
            <div class="p-2 border border-black dark:border-white bg-red-400 text-black dark:bg-gray-500 dark:text-white font-bold"> <%= hour %>:00 </div>
            <%= for day <- ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"] do %>
              <div
                data-date={day}
                data-time={"#{hour}:00"}
                class="p-2 border border-black dark:border-white schedule-block hover:bg-sky-500"
              ></div>
            <% end %>
          <% end %>
        </div>
      </div>

      <div id="task-form" class="hidden absolute bg-gray-300 dark:bg-gray-800 p-4 border border-gray-300 rounded shadow-lg z-10 ">
        <.simple_form id="task-form-inner" for={%{}} phx-submit="save_task">
          <div>
            <.input
              label="Task Name"
              type="text"
              id="task-name"
              name="task_name"
              value={}
              placeholder="Enter task name"
              class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm"
              required/>
          </div>
          <div class="mt-4 grid grid-cols-2 gap-4">
            <div>
              <.input
                label="Start Date"
                type="select"
                id="start-date"
                name="start_date"
                value={}
                class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm"
                options={["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]}
                />
            </div>
            <div>
              <.input
                label="End Date"
                type="select"
                id="end-date"
                name="end_date"
                value={}
                class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm"
                options={["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]}
                />
            </div>
          </div>
          <div class="mt-4 grid grid-cols-2 gap-4">
            <div>
              <.input
                label="Start Time"
                type="select"
                id="start-time"
                name="start_time"
                value={}
                class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm"
                options={["0:00", "2:00", "4:00", "6:00", "8:00", "10:00", "12:00", "14:00", "16:00", "18:00", "20:00", "22:00"]}
                />
            </div>
            <div>
              <.input
                label="End Time"
                type="select"
                id="end-time"
                name="end_time"
                value={}
                class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm"
                options={["0:00", "2:00", "4:00", "6:00", "8:00", "10:00", "12:00", "14:00", "16:00", "18:00", "20:00", "22:00"]}
                />
            </div>
          </div>
          <div class="mt-4 flex justify-end">
            <button type="button" id="cancel-task" class="inline-flex justify-center py-2 px-4 mr-4 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-black bg-white hover:bg-gray-100">
              Cancel
            </button>
            <.button
              class="inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
              >
              Save Task
            </.button>
          </div>
        </.simple_form>
      </div>
    </div>
    """
  end
end
