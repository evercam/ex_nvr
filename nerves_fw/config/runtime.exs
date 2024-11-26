import Config

defmodule ConfigParser do
  def parse_integrated_turn_ip(ip) do
    case :inet.parse_address(to_charlist(ip)) do
      {:ok, parsed_ip} ->
        parsed_ip

      _error ->
        raise """
        Bad EXTERNAL IP format. Expected IPv4, got: #{inspect(ip)}
        """
    end
  end

  def parse_integrated_turn_port_range(range) do
    with [str1, str2] <- String.split(range, "-"),
         from when from in 0..65_535 <- String.to_integer(str1),
         to when to in from..65_535 and from <= to <- String.to_integer(str2) do
      {from, to}
    else
      _else ->
        raise("""
        Bad INTEGRATED_TURN_PORT_RANGE environment variable value. Expected "from-to", where `from` and `to` \
        are numbers between 0 and 65535 and `from` is not bigger than `to`, got: \
        #{inspect(range)}
        """)
    end
  end

  def parse_port_number(nil, _var_name), do: nil

  def parse_port_number(port, var_name) do
    with {port, _sufix} when port in 1..65535 <- Integer.parse(port) do
      port
    else
      _var ->
        raise(
          "Bad #{var_name} environment variable value. Expected valid port number, got: #{inspect(port)}"
        )
    end
  end
end

if config_env() == :prod do
  config :ex_nvr,
    integrated_turn_ip:
      System.get_env("EXTERNAL_IP", "127.0.0.1") |> ConfigParser.parse_integrated_turn_ip(),
    integrated_turn_domain: System.get_env("VIRTUAL_HOST", "localhost"),
    integrated_turn_port_range:
      System.get_env("INTEGRATED_TURN_PORT_RANGE", "30000-30100")
      |> ConfigParser.parse_integrated_turn_port_range(),
    integrated_turn_tcp_port:
      System.get_env("INTEGRATED_TURN_TCP_PORT")
      |> ConfigParser.parse_port_number("INTEGRATED_TURN_TCP_PORT"),
    integrated_turn_pkey: System.get_env("INTEGRATED_TURN_PKEY"),
    integrated_turn_cert: System.get_env("INTEGRATED_TURN_CERT")
end
