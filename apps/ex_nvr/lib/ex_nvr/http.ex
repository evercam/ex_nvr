defmodule ExNVR.HTTP do
  @moduledoc false

  @spec get(binary(), Keyword.t()) ::
          {:ok, Req.Response.t()} | {:error, Exception.t()}
  def get(url, opts \\ []) do
    call(:get, url, nil, opts)
  end

  @spec post(binary(), any(), Keyword.t()) ::
          {:ok, Req.Response.t()} | {:error, Exception.t()}
  def post(url, body, opts \\ []) do
    call(:post, url, body, opts)
  end

  @spec build_digest_auth(map(), Keyword.t()) :: {:ok, binary()} | {:error, binary()}
  def build_digest_auth(resp, opts) do
    with digest_opts when is_map(digest_opts) <- digest_auth_opts(resp, opts) do
      digest_auth = encode_digest(digest_opts)
      {:ok, digest_auth}
    end
  end

  defp call(method, url, body, opts) do
    opts = Keyword.merge(opts, method: method, url: url)

    result = do_call(method, body, opts)

    with {:ok, %{status: 401} = resp} <- result,
         {:ok, digest_auth} <- build_digest_auth(resp, opts) do
      opts = Keyword.merge(opts, auth_type: :digest, digest_auth: digest_auth)
      do_call(method, body, opts)
    else
      _other ->
        result
    end
  end

  defp digest_auth_opts(%{headers: headers}, opts) do
    headers
    |> Enum.map(fn {key, value} -> {String.downcase(key), value} end)
    |> Map.new()
    |> Map.fetch("www-authenticate")
    |> case do
      {:ok, ["Digest " <> digest]} ->
        build_digest_auth_opts(digest, opts)

      {:ok, "Digest " <> digest} ->
        build_digest_auth_opts(digest, opts)

      _other ->
        nil
    end
  end

  defp build_digest_auth_opts(digest, opts) do
    %{
      nonce: match_pattern("nonce", digest),
      realm: match_pattern("realm", digest),
      qop: match_pattern("qop", digest),
      username: opts[:username],
      password: opts[:password],
      method: Atom.to_string(opts[:method]) |> String.upcase(),
      path: URI.parse(opts[:url]).path
    }
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

  defp do_call(method, body, opts) when is_map(body) do
    Req.request(method: method, url: opts[:url], auth: auth_from_opts(opts), json: body)
  end

  defp do_call(method, body, opts) do
    Req.request(method: method, url: opts[:url], auth: auth_from_opts(opts), body: body)
  end

  defp auth_from_opts(opts) do
    case opts[:auth_type] do
      :bearer -> {:bearer, opts[:token]}
      :basic -> {:basic, "#{opts[:username]}:#{opts[:password]}"}
      :digest -> opts[:digest_auth]
      _other -> nil
    end
  end

  defp md5(value) do
    value
    |> Enum.join(":")
    |> IO.iodata_to_binary()
    |> :erlang.md5()
    |> Base.encode16(case: :lower)
  end
end
