defmodule ExNVRWeb.RemoteStorageListLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  alias ExNVR.RemoteStorages

  def render(assigns) do
    ~H"""
    <div class="grow">
      <div class="ml-4 sm:ml-0">
        <.link href={~p"/remote-storages/new"}>
          <.button>Add remote storage</.button>
        </.link>
      </div>

      <.table id="remote-storages" rows={@remote_storages}>
        <:col :let={remote_storage} label="Id"><%= remote_storage.id %></:col>
        <:col :let={remote_storage} label="Name"><%= remote_storage.name %></:col>
        <:col :let={remote_storage} label="Type"><%= remote_storage.type %></:col>
        <:col :let={remote_storage} label="Url"><%= remote_storage.url %></:col>
        <:action :let={remote_storage}>
          <.button
            id={"dropdownMenuIconButton_#{remote_storage.id}"}
            data-dropdown-toggle={"dropdownDots_#{remote_storage.id}"}
            class="text-sm ml-3 bg-gray-200 hover:bg-gray-200 text-zinc-900 dark:bg-gray-800 dark:hover:bg-gray-700 dark:text-gray-400"
          >
            <svg
              class="w-5 h-5"
              aria-hidden="true"
              fill="currentColor"
              viewBox="0 0 20 20"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path d="M10 6a2 2 0 110-4 2 2 0 010 4zM10 12a2 2 0 110-4 2 2 0 010 4zM10 18a2 2 0 110-4 2 2 0 010 4z" />
            </svg>
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
          </.button>
        </:action>
        <:action :let={remote_storage}>
          <.modal id={"delete-remote-storage-modal-#{remote_storage.id}"}>
            <div class="bg-white dark:bg-gray-800 m-8 rounded">
              <h2 class="text-xl text-white font-bold mb-4">
                Are you sure you want to delete this remote storage ?
              </h2>
              <div class="mt-4">
                <button
                  phx-click="delete-remote-storage"
                  phx-value-remote_storage_id={remote_storage.id}
                  class="bg-red-500 hover:bg-red-600 text-white py-2 px-4 rounded mr-4"
                >
                  Confirm
                </button>
                <button
                  phx-click={hide_modal("delete-remote-storage-modal-#{remote_storage.id}")}
                  class="bg-gray-300 hover:bg-gray-400 text-gray-800 py-2 px-4 rounded"
                >
                  Cancel
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
      {:ok, _remote_storage} ->
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
