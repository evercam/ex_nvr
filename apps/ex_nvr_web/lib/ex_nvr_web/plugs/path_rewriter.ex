defmodule ExNVRWeb.Plug.PathRewriter do
  @moduledoc false

  alias Plug.Conn

  def init(opts), do: opts

  def call(%Conn{} = conn, _opts) do
    case Enum.count(conn.path_info) < 2 do
      true ->
        conn

      false ->
        {upstream, path_infos} = List.pop_at(conn.path_info, 1)

        conn
        |> Conn.put_req_header("x-host", upstream)
        |> Map.put(:path_info, path_infos)
    end
  end
end
