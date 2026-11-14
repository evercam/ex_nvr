defmodule ExNVRWeb.TriggerConfigListLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  import ExNVR.Authorization

  alias ExNVR.Triggers

  def render(assigns) do
    ~H"""
    <div class="grow e-m-8">
      <div class="ml-4 sm:ml-0">
        <.link href={~p"/triggers/new"}>
          <.button><.icon name="hero-plus-solid" class="h-4 w-4" />Add Trigger</.button>
        </.link>
      </div>

      <.table id="trigger-configs" rows={@trigger_configs}>
        <:col :let={config} label="Name">{config.name}</:col>
        <:col :let={config} label="Enabled">
          <span :if={config.enabled} class="text-green-500">Yes</span>
          <span :if={!config.enabled} class="text-gray-400">No</span>
        </:col>
        <:col :let={config} label="Sources">{length(config.source_configs)}</:col>
        <:col :let={config} label="Targets">{length(config.target_configs)}</:col>
        <:col :let={config} label="Devices">{length(config.devices)}</:col>
        <:action :let={config}>
          <.three_dot
            id={"dropdownMenuIconButton_#{config.id}"}
            dropdown_id={"dropdownDots_#{config.id}"}
          />

          <div
            id={"dropdownDots_#{config.id}"}
            class="z-10 hidden text-left bg-white divide-y divide-gray-100 rounded-lg shadow w-44 dark:bg-gray-700 dark:divide-gray-600"
          >
            <ul
              class="py-2 text-sm text-gray-700 dark:text-gray-200"
              aria-labelledby={"dropdownMenuIconButton_#{config.id}"}
            >
              <li>
                <.link
                  href={~p"/triggers/#{config.id}"}
                  class="block px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
                >
                  Update
                </.link>
              </li>
              <li>
                <.link
                  phx-click={show_modal("delete-trigger-modal-#{config.id}")}
                  class="block px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
                >
                  Delete
                </.link>
              </li>
            </ul>
          </div>
        </:action>
        <:action :let={config}>
          <.modal id={"delete-trigger-modal-#{config.id}"}>
            <div class="p-6">
              <div class="flex items-start gap-4">
                <div class="flex-shrink-0 flex items-center justify-center w-10 h-10 rounded-full bg-red-100 dark:bg-red-900/30">
                  <.icon
                    name="hero-exclamation-triangle"
                    class="w-5 h-5 text-red-600 dark:text-red-400"
                  />
                </div>
                <div>
                  <h3 class="text-base font-semibold text-gray-900 dark:text-white">
                    Delete trigger?
                  </h3>
                  <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                    Are you sure you want to delete <span class="font-medium text-gray-700 dark:text-gray-300">{config.name}</span>?
                    This action cannot be undone.
                  </p>
                </div>
              </div>
              <div class="mt-6 flex justify-end gap-3">
                <button
                  phx-click={hide_modal("delete-trigger-modal-#{config.id}")}
                  class="px-4 py-2 rounded-lg text-sm font-medium bg-white text-gray-700 ring-1 ring-gray-300 hover:bg-gray-50 dark:bg-gray-700 dark:text-gray-300 dark:ring-gray-600 dark:hover:bg-gray-600"
                >
                  Cancel
                </button>
                <button
                  phx-click="delete-trigger"
                  phx-value-trigger_id={config.id}
                  class="px-4 py-2 rounded-lg text-sm font-medium bg-red-600 text-white hover:bg-red-700 dark:bg-red-700 dark:hover:bg-red-600"
                >
                  Delete
                </button>
              </div>
            </div>
          </.modal>
        </:action>
      </.table>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, trigger_configs: Triggers.list_trigger_configs())}
  end

  def handle_event("delete-trigger", %{"trigger_id" => trigger_id}, socket) do
    user = socket.assigns.current_user
    trigger = Triggers.get_trigger_config!(String.to_integer(trigger_id))

    with :ok <- authorize(user, :trigger, :delete),
         {:ok, _} <- Triggers.delete_trigger_config(trigger) do
      socket
      |> assign(trigger_configs: Triggers.list_trigger_configs())
      |> put_flash(:info, "Trigger #{trigger.name} deleted")
      |> then(&{:noreply, &1})
    else
      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to perform this action")}

      _other ->
        {:noreply, put_flash(socket, :error, "Could not delete trigger")}
    end
  end
end
