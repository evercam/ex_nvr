defmodule ExNVRWeb.RemoteStorageListLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  alias ExNVR.RemoteStorages

  def render(assigns) do
    ~H"""
    <div class="grow e-m-8">
      <div class="ml-4 sm:ml-0">
        <.link href={~p"/remote-storages/new"}>
          <.button><.icon name="hero-plus-solid" class="h-4 w-4" />Add Remote Storage</.button>
        </.link>
      </div>

      <.table id="remote-storages" rows={@remote_storages}>
        <:col :let={remote_storage} label="Id">{remote_storage.id}</:col>
        <:col :let={remote_storage} label="Name">{remote_storage.name}</:col>
        <:col :let={remote_storage} label="Type">{remote_storage.type}</:col>
        <:col :let={remote_storage} label="Url">{remote_storage.url}</:col>
        <:action :let={remote_storage}>
          <.three_dot
            id={"dropdownMenuIconButton_#{remote_storage.id}"}
            dropdown_id={"dropdownDots_#{remote_storage.id}"}
          />

          <div
            id={"dropdownDots_#{remote_storage.id}"}
            class="z-10 hidden text-left bg-white divide-y divide-gray-100 rounded-lg shadow w-44 dark:bg-gray-700 dark:divide-gray-600"
          >
            <ul
              class="py-2 text-sm text-gray-700 dark:text-gray-200"
              aria-labelledby={"dropdownMenuIconButton_#{remote_storage.id}"}
            >
              <li>
                <.link
                  href={~p"/remote-storages/#{remote_storage.id}"}
                  class="block px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
                >
                  Update
                </.link>
              </li>
              <li>
                <.link
                  phx-click={show_modal("delete-remote-storage-modal-#{remote_storage.id}")}
                  class="block px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
                >
                  Delete
                </.link>
              </li>
            </ul>
          </div>
        </:action>
        <:action :let={remote_storage}>
          <.modal id={"delete-remote-storage-modal-#{remote_storage.id}"}>
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
                    Delete remote storage?
                  </h3>
                  <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                    Are you sure you want to delete <span class="font-medium text-gray-700 dark:text-gray-300">{remote_storage.name}</span>?
                    This action cannot be undone.
                  </p>
                </div>
              </div>
              <div class="mt-6 flex justify-end gap-3">
                <button
                  phx-click={hide_modal("delete-remote-storage-modal-#{remote_storage.id}")}
                  class="px-4 py-2 rounded-lg text-sm font-medium bg-white text-gray-700 ring-1 ring-gray-300 hover:bg-gray-50 dark:bg-gray-700 dark:text-gray-300 dark:ring-gray-600 dark:hover:bg-gray-600"
                >
                  Cancel
                </button>
                <button
                  phx-click="delete-remote-storage"
                  phx-value-remote_storage_id={remote_storage.id}
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
    {:ok, assign(socket, remote_storages: RemoteStorages.list())}
  end

  def handle_event("delete-remote-storage", %{"remote_storage_id" => remote_storage_id}, socket) do
    remote_storage = RemoteStorages.get!(remote_storage_id)

    case RemoteStorages.delete(remote_storage) do
      :ok ->
        socket
        |> assign(remote_storages: RemoteStorages.list())
        |> put_flash(:info, "Remote storage #{remote_storage.name} deleted")
        |> then(&{:noreply, &1})

      _other ->
        socket
        |> put_flash(:error, "could not delete remote_storage")
        |> redirect(to: ~p"/remote-storages")
        |> then(&{:noreply, &1})
    end
  end
end
