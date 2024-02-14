defmodule ExNVR.HTTP do
  @moduledoc false

  @spec get(binary(), Keyword.t()) ::
          {:ok, Finch.Response.t()} | {:error, term()}
  def get(url, opts \\ []) do
    username = opts[:username] || ""
    password = opts[:password] || ""

    opts = opts ++ [method: :get, url: url]

    if username == "" or password == "" do
      do_call(:get, url)
    else
      http_headers = [{"Authorization", "Basic " <> Base.encode64(username <> ":" <> password)}]
      result = do_call(:get, url, http_headers)

      with {:ok, %{status: 401} = resp} <- result,
           {:ok, digest_header} <- build_digest_auth_header(resp, opts) do
        do_call(:get, url, [digest_header])
      else
        _other ->
          result
      end
    end
  end

  def post(url, headers, body) do
    do_call(:post, url, headers, body)
  end

  @spec build_digest_auth_header(map(), Keyword.t()) :: {:ok, tuple()} | {:error, binary()}
  def build_digest_auth_header(resp, opts) do
    with digest_opts when is_map(digest_opts) <- digest_auth_opts(resp, opts),
         digest_header <- {"Authorization", encode_digest(digest_opts)} do
      {:ok, digest_header}
    end
  end

  defp digest_auth_opts(%{headers: headers}, opts) do
    headers
    |> Enum.map(fn {key, value} -> {String.downcase(key), value} end)
    |> Map.new()
    |> Map.fetch("www-authenticate")
    |> case do
      {:ok, "Digest " <> digest} ->
        %{
          nonce: match_pattern("nonce", digest),
          realm: match_pattern("realm", digest),
          qop: match_pattern("qop", digest),
          username: opts[:username],
          password: opts[:password],
          method: Atom.to_string(opts[:method]) |> String.upcase(),
          path: URI.parse(opts[:url]).path
        }

      _other ->
        nil
    end
  end

  defp match_pattern(pattern, digest) do
    case Regex.run(~r/#{pattern}=\"(?<value>.*)\"/U, digest) do
      [_match, value] -> value
      _other -> nil
    end
  end

  defp encode_digest(opts) do
    ha1 = md5([opts.username, opts.realm, opts.password])
    ha2 = md5([opts.method, opts.path])
    nonce_count = "00000001"
    client_nonce = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    response = digest_response_attribute(ha1, ha2, opts, nonce_count, client_nonce)

    digest_token =
      %{
        "username" => opts.username,
        "realm" => opts.realm,
        "nonce" => opts.nonce,
        "uri" => opts.path,
        "response" => response,
        "qop" => opts.qop,
        "cnonce" => client_nonce,
        "nc" => nonce_count
      }
      |> Map.filter(fn {_key, value} -> value != nil end)
      |> Enum.map_join(", ", fn {key, value} -> ~s(#{key}="#{value}") end)

    "Digest " <> digest_token
  end

  defp digest_response_attribute(ha1, ha2, %{qop: nil} = opts, _nonce_count, _client_nonce) do
    md5([ha1, opts.nonce, ha2])
  end

  defp digest_response_attribute(ha1, ha2, opts, nonce_count, client_nonce) do
    md5([ha1, opts.nonce, nonce_count, client_nonce, opts.qop, ha2])
  end

  defp do_call(method, url, headers \\ [], body \\ nil, opts \\ []) do
    Finch.build(method, url, headers, body) |> Finch.request(ExNVR.Finch, opts)
  end

  defp md5(value) do
    value
    |> Enum.join(":")
    |> IO.iodata_to_binary()
    |> :erlang.md5()
    |> Base.encode16(case: :lower)
  end
end
