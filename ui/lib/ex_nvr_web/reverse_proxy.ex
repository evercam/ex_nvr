defmodule ExNVRWeb.ReverseProxy do
  @moduledoc false

  require Logger

  import Plug.Conn

  @private_ips [
    {{10, 0, 0, 0}, {10, 255, 255, 255}},
    {{172, 16, 0, 0}, {172, 31, 255, 255}},
    {{192, 168, 0, 0}, {192, 168, 255, 255}}
  ]

  def reverse_proxy(conn) do
    %URI{scheme: get_scheme(conn), host: validate_host(conn)} |> URI.to_string()
  end

  def handle_error(error, conn) do
    Logger.error("error occurred while trying to reverse proxy request: #{inspect(error)}")
    send_resp(conn, 500, "Internal Server Error")
  end

  defp validate_host(conn) do
    with [addr] <- get_req_header(conn, "x-host"),
         {:ok, ip_addr} <- :inet.parse_ipv4_address(to_charlist(addr)),
         true <- Enum.any?(@private_ips, &(elem(&1, 0) < ip_addr and elem(&1, 1) > ip_addr)) do
      :inet.ntoa(ip_addr) |> to_string()
    else
      _reason ->
        UUID.uuid4()
    end
  end

  defp get_scheme(conn) do
    case get_req_header(conn, "x-scheme") do
      [scheme] when scheme in ["http", "https"] -> scheme
      _other -> "http"
    end
  end
end
