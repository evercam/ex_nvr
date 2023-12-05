defmodule ExNVRWeb.Live.Helpers do
  @moduledoc """
  Helper functions for live views.
  """

  import Phoenix.LiveView

  def unauthorized(socket, redirect_to, reply) do
    socket
    |> put_flash(:error, "You are not authorized to perform this action!")
    |> redirect(to: redirect_to)
    |> then(&{reply, &1})
  end
end
