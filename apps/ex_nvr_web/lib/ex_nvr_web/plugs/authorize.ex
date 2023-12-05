defmodule ExNVRWeb.Plug.Authorize do
  import Plug.Conn
  import Phoenix.Controller
  import ExNVR.Authorization
  import ExNVRWeb.Controller.Helpers

  def init(opts), do: opts

  def call(conn, opts) do
    role = conn.assigns.current_user.role
    resource = Keyword.get(opts, :resource)
    action = action_name(conn)

    check(action, role, resource)
    |> maybe_continue(conn)
  end

  defp maybe_continue(true, conn), do: conn

  defp maybe_continue(false, conn) do
    conn
    |> unauthorized()
    |> halt()
  end

  defp check(action, role, resource) when action in [:index, :show],
    do: is_authorized?(role, resource, :read)

  defp check(action, role, resource) when action in [:new, :create],
    do: is_authorized?(role, resource, :create)

  defp check(action, role, resource) when action in [:edit, :update],
    do: is_authorized?(role, resource, :update)

  defp check(:delete, role, resource), do: is_authorized?(role, resource, :delete)
  defp check(_action, _role, _resource), do: false
end
