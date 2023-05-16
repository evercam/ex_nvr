defmodule ExNVRWeb.Controller.Helpers do
  @moduledoc """
  Helper functions for controllers/Plugs
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Plug.Conn
  alias ExNVRWeb.ErrorJSON

  @spec not_found(Conn.t()) :: Conn.t()
  def not_found(conn) do
    conn
    |> put_status(404)
    |> put_view(ErrorJSON)
    |> render("404.json")
  end
end
