defmodule ExNVRWeb.UserListLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  alias ExNVR.Accounts

  def render(assigns) do
    ~H"""
    <div class="grow">
      <div :if={@current_user.role == :admin} class="ml-4 sm:ml-0">
        <.link href={~p"/users/new"}>
          <.button>Add User</.button>
        </.link>
      </div>

      <.table id="users" rows={@users}>
        <:col :let={user} label="Id"><%= user.id %></:col>
        <:col :let={user} label="First Name"><%= user.first_name %></:col>
        <:col :let={user} label="Last Name"><%= user.last_name %></:col>
        <:col :let={user} label="Username"><%= user.username %></:col>
        <:col :let={user} label="Email"><%= user.email %></:col>
        <:col :let={user} label="Role">
          <div class="flex items-center">
            <%= String.upcase(to_string(user.role)) %>
          </div>
        </:col>
        <:col :let={user} label="Language">
          <div class="flex items-center">
            <%= String.upcase(to_string(user.language)) %>
          </div>
        </:col>
        <:action :let={user}>
          <.button
            :if={@current_user.role == :admin}
            id={"dropdownMenuIconButton-#{user.id}"}
            data-dropdown-toggle={"dropdownDots-#{user.id}"}
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
                    phx-click={show_modal("delete-modal")}
                  >
                    Delete
                  </.link>
                </li>
              </ul>
            </div>
          </.button>
          <.modal id="delete-modal">
            <div class="bg-blue-300 p-4 rounded-lg text-center dark:bg-gray-800 dark:border-gray-700">
              <p class="text-l text-black dark:text-white font-bold mb-4">
                <%= "Are you sure you want to delete the User: '#{user.email}'" %>
              </p>
              <.button
                phx-disable-with="Deleting..."
                phx-click={JS.push("delete", value: %{id: user.id})}
                class="text-black bg-red-500 hover:bg-red-400 px-4 py-2 mx-2 rounded hover:bg-red-600 dark:text-white"
              >
                Yes
              </.button>
              <.button
                phx-click={hide_modal("delete-modal")}
                class="text-black bg-gray-300 hover:bg-gray-200 px-4 py-2 mx-2 rounded hover:bg-red-600 dark:text-white"
              >
                Cancel
              </.button>
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
