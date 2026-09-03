defmodule ExNVR.HttpTest do
  use ExNVR.DataCase

  alias ExNVR.HTTP
  alias Plug.Conn

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  test "client handle digest authentication", %{bypass: bypass} do
    Bypass.expect(bypass, "GET", "/resource", fn conn ->
      case Conn.get_req_header(conn, "authorization") do
        ["Basic " <> _token] ->
          conn
          |> Conn.put_resp_header(
            "www-authenticate",
            "Digest realm=\"realm\", nonce=\"1fd54f4d5f5d4sfdsf\", qop=\"auth\""
          )
          |> Conn.resp(401, "")

        ["Digest " <> _token] ->
          conn
          |> Conn.put_resp_content_type("plain/text")
          |> Conn.resp(200, ~s(success))
      end
    end)

    opts = [username: "admin", password: "password", auth_type: :basic]
    response = HTTP.get("#{url(bypass.port)}/resource", opts)
    assert {:ok, %{status: 200, body: ~s<success>}} = response
  end

  defp url(port), do: "http://localhost:#{port}"
end
