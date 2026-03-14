defmodule ExNVRWeb.DeviceTabs.TriggersTab do
  @moduledoc false

  use ExNVRWeb, :live_component

  alias ExNVR.Triggers

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 shadow-sm overflow-hidden">
        <div class="px-5 py-3.5 border-b border-gray-200 dark:border-gray-700 flex items-center justify-between">
          <h3 class="text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-widest">
            Trigger Configurations
          </h3>
          <.link
            href={~p"/triggers/new"}
            class="text-sm text-blue-600 dark:text-blue-400 hover:underline"
          >
            Create new trigger
          </.link>
        </div>

        <div :if={@all_triggers == []} class="px-5 py-8 text-center">
          <p class="text-sm text-gray-500 dark:text-gray-400">
            No triggers have been created yet.
          </p>
          <.link
            href={~p"/triggers/new"}
            class="mt-2 inline-block text-sm text-blue-600 dark:text-blue-400 hover:underline"
          >
            Create your first trigger
          </.link>
        </div>

        <div :if={@all_triggers != []} class="divide-y divide-gray-100 dark:divide-gray-700">
          <label
            :for={tc <- @all_triggers}
            class="flex items-center gap-4 px-5 py-3.5 hover:bg-gray-50 dark:hover:bg-gray-700/50 cursor-pointer transition-colors"
          >
            <input
              type="checkbox"
              checked={tc.id in @selected_ids}
              phx-click="toggle-trigger"
              phx-value-trigger-id={tc.id}
              phx-target={@myself}
              class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 dark:bg-gray-700 dark:border-gray-600"
            />
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <span class="text-sm font-medium text-gray-900 dark:text-white">{tc.name}</span>
                <span
                  :if={!tc.enabled}
                  class="text-xs text-gray-400 bg-gray-200 dark:bg-gray-600 px-2 py-0.5 rounded"
                >
                  disabled
                </span>
              </div>
              <p class="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                {length(tc.source_configs)} source(s), {length(tc.target_configs)} target(s)
              </p>
            </div>
            <.link
              href={~p"/triggers/#{tc.id}"}
              class="text-xs text-blue-600 dark:text-blue-400 hover:underline"
              phx-click={:stop_propagation}
            >
              Edit
            </.link>
          </label>
        </div>
      </div>

      <div
        :if={@saved}
        class="flex items-center gap-1.5 text-sm text-green-600 dark:text-green-400"
      >
        <svg class="w-4 h-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M5 13l4 4L19 7"
          />
        </svg>
        Saved
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    device = assigns.device

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:all_triggers, fn -> Triggers.list_trigger_configs() end)
     |> assign_new(:selected_ids, fn ->
       Triggers.trigger_configs_for_device(device.id) |> Enum.map(& &1.id)
     end)
     |> assign_new(:saved, fn -> false end)}
  end

  @impl true
  def handle_event("toggle-trigger", %{"trigger-id" => trigger_id}, socket) do
    trigger_id = String.to_integer(trigger_id)
    selected = socket.assigns.selected_ids

    selected =
      if trigger_id in selected,
        do: List.delete(selected, trigger_id),
        else: [trigger_id | selected]

    Triggers.set_device_trigger_configs(socket.assigns.device.id, selected)

    {:noreply, assign(socket, selected_ids: selected, saved: true)}
  end
end
