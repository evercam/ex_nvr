defmodule ExNVRWeb.Plug.ProxyAllow do
  @moduledoc """
  Check if reverse proxy requests are allowed
  """

  import ExNVRWeb.Controller.Helpers

  alias Plug.Conn

  def init(opts), do: opts

  def call(%Conn{} = conn, _opts) do
    if Application.get_env(:ex_nvr, :enable_reverse_proxy, false),
      do: conn,
      else: not_found(conn)
  end
end
