defmodule ExNVRWeb.Plug.Authorize do
  import Plug.Conn
  import Phoenix.Controller
  import ExNVR.Authorization
  import ExNVRWeb.Controller.Helpers

  def init(opts), do: opts

  def call(conn, opts) do
    user = conn.assigns.current_user
    resource = Keyword.get(opts, :resource)
    action = action_name(conn)

    check(action, user, resource)
    |> maybe_continue(conn)
  end

  defp maybe_continue(true, conn), do: conn

  defp maybe_continue(false, conn) do
    conn
    |> unauthorized()
    |> halt()
  end

  defp check(action, user, resource) when action in [:index, :show],
    do:
      if({:ok, :authorized} = authorized?(user, resource, :read),
        do: true,
        else: false
      )

  defp check(action, user, resource) when action in [:new, :create],
    do:
      if({:ok, :authorized} = authorized?(user, resource, :create),
        do: true,
        else: false
      )

  defp check(action, user, resource) when action in [:edit, :update],
    do:
      if({:ok, :authorized} = authorized?(user, resource, :update),
        do: true,
        else: false
      )

  defp check(:delete, user, resource),
    do:
      if({:ok, :authorized} = authorized?(user, resource, :delete),
        do: true,
        else: false
      )

  defp check(_action, _user, _resource), do: false
end
