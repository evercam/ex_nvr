defmodule ExNVRWeb.UserLoginLive do
  use ExNVRWeb, :live_view

  def render(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <div class="flex flex-col items-center justify-center h-screen bg-gray-50 dark:bg-gray-900">
      <div class="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-6 w-full max-w-sm">
        <.header class="text-center">
          <span class="text-gray-900 dark:text-white">Sign in to account</span>
        </.header>

        <.simple_form
          for={@form}
          id="login_form"
          action={~p"/users/login"}
          phx-update="ignore"
        >
          <.input field={@form[:email]} type="email" label="Email" required />
          <.input field={@form[:password]} type="password" label="Password" required />

          <:actions>
            <.input field={@form[:remember_me]} type="checkbox" label="Keep me logged in" />
            <.link href={~p"/users/reset-password"} class="text-sm font-semibold dark:text-white">
              Forgot your password?
            </.link>
          </:actions>
          <:actions>
            <.button phx-disable-with="Signing in..." class="w-full">
              Sign in <span aria-hidden="true">→</span>
            </.button>
          </:actions>
        </.simple_form>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form], layout: false}
  end
end
