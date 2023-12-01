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
    do: can(role) |> read?(resource)

  defp check(action, role, resource) when action in [:hls_stream, :hls_stream_segment, :snapshot],
    do: can(role) |> stream?(resource)

  defp check(action, role, resource) when action in [:footage, :bif, :blob],
    do: can(role) |> download_archives?(resource)

  defp check(action, role, resource) when action in [:new, :create],
    do: can(role) |> create?(resource)

  defp check(action, role, resource) when action in [:edit, :update],
    do: can(role) |> update?(resource)

  defp check(:delete, role, resource), do: can(role) |> delete?(resource)
  defp check(_action, _role, _resource), do: false
end
