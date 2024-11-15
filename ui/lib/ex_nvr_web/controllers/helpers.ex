defmodule ExNVRWeb.Controller.Helpers do
  @moduledoc """
  Helper functions for controllers/Plugs
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Plug.Conn
  alias ExNVRWeb.ErrorJSON

  @spec not_found(Conn.t()) :: Conn.t()
  def not_found(conn), do: render_error(conn, 404)

  @spec unauthorized(Conn.t()) :: Conn.t()
  def unauthorized(conn), do: render_error(conn, 401)

  @spec forbidden(Conn.t()) :: Conn.t()
  def forbidden(conn), do: render_error(conn, 403)

  defp render_error(conn, status) do
    conn
    |> put_status(status)
    |> put_view(ErrorJSON)
    |> render("#{status}.json")
    |> halt()
  end
end
