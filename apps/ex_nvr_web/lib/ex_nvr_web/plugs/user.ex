defmodule ExNVRWeb.Plug.User do
  @moduledoc """
  Loads the user instance from database
  """

  import ExNVRWeb.Controller.Helpers

  require Logger

  alias ExNVR.Accounts
  alias Plug.Conn

  def init(opts), do: opts

  def call(%Conn{} = conn, opts) do
    field_name = Keyword.get(opts, :field_name, "user_id")
    user_id = conn.path_params[field_name]

    case Accounts.get_user(user_id) do
      %Accounts.User{} = user ->
        Logger.metadata(user_id: user.id)
        Conn.assign(conn, :user_instance, user)

      nil ->
        conn
        |> not_found()
        |> Conn.halt()
    end
  end
end
