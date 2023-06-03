defmodule ExNVRWeb.PageController do
  use ExNVRWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/dashboard")
  end
end
