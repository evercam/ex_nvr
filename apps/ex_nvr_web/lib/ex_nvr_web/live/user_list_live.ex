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
            id={"dropdownMenuIconButton_#{user.id}"}
            data-dropdown-toggle={"dropdownDots_#{user.id}"}
            class="text-sm ml-3 hover:bg-gray-100 dark:bg-gray-800"
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
              id={"dropdownDots_#{user.id}"}
              class="z-10 hidden text-left bg-white divide-y divide-gray-100 rounded-lg shadow w-44 dark:bg-gray-700 dark:divide-gray-600"
            >
              <ul
                class="py-2 text-sm text-gray-700 dark:text-gray-200"
                aria-labelledby={"dropdownMenuIconButton_#{user.id}"}
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
                    href="#"
                    class="block px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-red"
                    phx-click={JS.remove_class("hidden", to: "#confirm_delete_modal")}
                    phx-value-confirm="Are you sure you want to delete this user?"
                  >
                    Delete
                  </.link>
                </li>
              </ul>
            </div>
          </.button>
          <div
            id="confirm_delete_modal"
            class="hidden fixed top-0 right-0 bottom-0 left-0 flex justify-center items-center bg-black bg-opacity-70 z-50"
          >
            <div class="confirm-dialog bg-white p-4 rounded-lg text-center border-b border-gray-200 dark:bg-gray-800 dark:border-gray-700">
              <p class="text-white mb-10 mt-10">
                <%= "Are you sure you want to delete the User: '#{user.email}'" %>
              </p>
              <.button
                phx-click={
                  JS.push("delete", value: %{id: user.id})
                  |> JS.add_class("hidden", to: "#confirm_delete_modal")
                }
                class="bg-red-500 text-white px-4 py-2 mx-2 rounded hover:bg-red-600"
              >
                Yes
              </.button>
              <.button
                phx-click={JS.add_class("hidden", to: "#confirm_delete_modal")}
                class="bg-gray-500 text-white px-4 py-2 mx-2 rounded hover:bg-gray-600"
              >
                No
              </.button>
            </div>
          </div>
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
