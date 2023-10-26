defmodule ExNVRWeb.UserListLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  alias ExNVR.Accounts.User
  alias ExNVR.Accounts

  def render(assigns) do
    ~H"""
    <div class="grow">
      <div class="ml-4 sm:ml-0">
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
              </ul>
            </div>
          </.button>
        </:action>
      </.table>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, users: Accounts.list())}
  end
end
