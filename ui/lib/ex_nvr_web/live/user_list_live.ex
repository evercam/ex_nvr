defmodule ExNVRWeb.UserListLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  alias ExNVR.Accounts

  def render(assigns) do
    ~H"""
    <div class="grow e-m-8">
      <div :if={@current_user.role == :admin} class="ml-4 sm:ml-0">
        <.link href={~p"/users/new"}>
          <.button><.icon name="hero-plus-solid" class="h-4 w-4" />Add User</.button>
        </.link>
      </div>

      <.table id="users" rows={@users}>
        <:col :let={user} label="Id">{user.id}</:col>
        <:col :let={user} label="First Name">{user.first_name}</:col>
        <:col :let={user} label="Last Name">{user.last_name}</:col>
        <:col :let={user} label="Username">{user.username}</:col>
        <:col :let={user} label="Email">{user.email}</:col>
        <:col :let={user} label="Role">
          <div class="flex items-center">
            {String.upcase(to_string(user.role))}
          </div>
        </:col>
        <:col :let={user} label="Language">
          <div class="flex items-center">
            {String.upcase(to_string(user.language))}
          </div>
        </:col>
        <:action :let={user}>
          <.three_dot
            :if={@current_user.role == :admin}
            id={"dropdownMenuIconButton-#{user.id}"}
            dropdown_id={"dropdownDots-#{user.id}"}
          />
          <div
            id={"dropdownDots-#{user.id}"}
            class="z-10 hidden text-left bg-white divide-y divide-gray-100 rounded-lg shadow w-44 dark:bg-gray-700 dark:divide-gray-600"
          >
            <ul
              class="py-2 text-sm text-gray-700 dark:text-gray-200"
              aria-labelledby={"dropdownMenuIconButton-#{user.id}"}
            >
              <li>
                <.link
                  href={~p"/users/#{user.id}"}
                  class="block px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
                >
                  Update
                </.link>
              </li>
              <li>
                <.link
                  id={"delete_user-#{user.id}"}
                  href="#"
                  class="block px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-red"
                  phx-click={show_modal("delete-modal-#{user.id}")}
                >
                  Delete
                </.link>
              </li>
            </ul>
          </div>
          <.modal id={"delete-modal-#{user.id}"}>
            <div class="p-6">
              <div class="flex items-start gap-4">
                <div class="flex-shrink-0 flex items-center justify-center w-10 h-10 rounded-full bg-red-100 dark:bg-red-900/30">
                  <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-red-600 dark:text-red-400" />
                </div>
                <div>
                  <h3 class="text-base font-semibold text-gray-900 dark:text-white">Delete user?</h3>
                  <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                    Are you sure you want to delete
                    <span class="font-medium text-gray-700 dark:text-gray-300">{user.email}</span>?
                    This action cannot be undone.
                  </p>
                </div>
              </div>
              <div class="mt-6 flex justify-end gap-3">
                <button
                  phx-click={hide_modal("delete-modal-#{user.id}")}
                  class="px-4 py-2 rounded-lg text-sm font-medium bg-white text-gray-700 ring-1 ring-gray-300 hover:bg-gray-50 dark:bg-gray-700 dark:text-gray-300 dark:ring-gray-600 dark:hover:bg-gray-600"
                >
                  Cancel
                </button>
                <button
                  phx-disable-with="Deleting..."
                  phx-click={JS.push("delete", value: %{id: user.id})}
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
    {:ok, assign(socket, users: Accounts.list())}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)
    email = user.email

    case Accounts.delete_user(user) do
      {:ok, _deleted_user} ->
        info = "User: '#{email}' has been deleted"

        socket
        |> assign(users: Accounts.list())
        |> put_flash(:info, info)
        |> then(&{:noreply, &1})

      {:error, _} ->
        error = "An error has occured!"

        socket
        |> put_flash(:error, error)
        |> then(&{:noreply, &1})
    end
  end
end
