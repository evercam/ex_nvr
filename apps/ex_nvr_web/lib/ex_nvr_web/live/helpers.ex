defmodule ExNVRWeb.Live.Helpers do
  @moduledoc """
  Helper functions for live views.
  """

  import Phoenix.LiveView

  def unauthorized(socket, reply) do
    socket
    |> put_flash(:error, "You are not authorized to perform this action!")
    |> then(&{reply, &1})
  end
end
