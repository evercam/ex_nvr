defmodule ExNVRWeb.UserLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  alias ExNVR.{Accounts}
  alias ExNVR.Accounts.User

  def mount(%{"id" => "new"}, _session, socket) do
    changeset = Accounts.change_user_registration(%User{})
    {:ok, assign(socket, user: %User{}, user_form: to_form(changeset))}
  end

  def mount(%{"id" => user_id}, _session, socket) do
    user = Accounts.get_user!(user_id)
    {:ok, assign(socket, user: user, user_form: to_form(Accounts.change_user_update(user)))}
  end

  def handle_event("save_user", %{"user" => user_params}, socket) do
    user = socket.assigns.user

    if user.id,
      do: do_update_user(socket, user, user_params),
      else: do_save_user(socket, user_params)
  end

  defp do_save_user(socket, user_params) do
    case Accounts.register_user(user_params) do
      {:ok, _user} ->
        info = "User created successfully"

        socket
        |> put_flash(:info, info)
        |> redirect(to: ~p"/users")
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply,
         assign(
           socket,
           user_form: to_form(changeset)
         )}
    end
  end

  defp do_update_user(socket, user, user_params) do
    case Accounts.update_user(user, user_params) do
      {:ok, updated_user} ->
        info = "User updated successfully"

        socket
        |> put_flash(:info, info)
        |> assign(
          user: updated_user,
          user_form: to_form(Accounts.change_user_registration(updated_user))
        )
        |> redirect(to: ~p"/users")
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           user_form: to_form(changeset)
         )}
    end
  end
end
