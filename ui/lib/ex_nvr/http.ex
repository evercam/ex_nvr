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

  defp call(method, url, body, opts) do
    opts = Keyword.merge(opts, method: method, url: url)
    do_call(method, body, opts)
  end

  defp do_call(method, body, opts) when is_map(body) do
    build_request(method, opts) |> Req.request(json: body, auth: auth_from_opts(opts))
  end

  defp do_call(method, body, opts) do
    build_request(method, opts) |> Req.request(body: body, auth: auth_from_opts(opts))
  end

  defp build_request(method, opts) do
    Req.Request.new(method: method, url: opts[:url], adapter: http_poison_adapter())
    |> Req.Steps.attach()
    |> Req.Request.prepend_response_steps(
      digest_auth: fn params -> digest_auth(params, {opts[:username], opts[:password]}) end
    )
  end

  defp auth_from_opts(opts) do
    case opts[:auth_type] do
      :bearer -> {:bearer, opts[:token]}
      :basic -> {:basic, "#{opts[:username]}:#{opts[:password]}"}
      _other -> nil
    end
  end

  # Digest auth step for Req
  defp digest_auth({request, %{status: 401} = response}, {username, password}) do
    with ["Digest " <> digest | _] <- Req.Response.get_header(response, "www-authenticate"),
         true <- not is_nil(username) and not is_nil(password) do
      digest =
        digest
        |> build_digest_auth_opts(request.method, request.url, username, password)
        |> encode_digest()

      request
      |> Req.Request.put_header("Authorization", digest)
      |> Req.Request.run_request()
    else
      _other -> {request, response}
    end
  end

  defp digest_auth({request, response}, _credentials), do: {request, response}

  defp build_digest_auth_opts(digest, method, url, username, password) do
    %{
      nonce: match_pattern("nonce", digest),
      realm: match_pattern("realm", digest),
      qop: match_pattern("qop", digest),
      username: username,
      password: password,
      method: Atom.to_string(method) |> String.upcase(),
      path: url.path
    }
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

  defp match_pattern(pattern, digest) do
    case Regex.run(~r/#{pattern}=\"(?<value>.*)\"/U, digest) do
      [_match, value] -> value
      _other -> nil
    end
  end

  defp digest_response_attribute(ha1, ha2, %{qop: nil} = opts, _nonce_count, _client_nonce) do
    md5([ha1, opts.nonce, ha2])
  end

  defp digest_response_attribute(ha1, ha2, opts, nonce_count, client_nonce) do
    md5([ha1, opts.nonce, nonce_count, client_nonce, opts.qop, ha2])
  end

  defp md5(value) do
    value
    |> Enum.join(":")
    |> IO.iodata_to_binary()
    |> :erlang.md5()
    |> Base.encode16(case: :lower)
  end

  defp http_poison_adapter do
    fn req ->
      case HTTPoison.request(
             req.method,
             URI.to_string(req.url),
             req.body || "",
             req.headers
           ) do
        {:ok, resp} ->
          {req,
           %Req.Response{
             status: resp.status_code,
             headers: headers_to_map(resp.headers),
             body: resp.body
           }}

        {:error, reason} ->
          {req, reason}
      end
    end
  end

  defp headers_to_map(headers) do
    Enum.reduce(headers, %{}, fn {key, value}, acc ->
      key = String.downcase(key, :ascii)
      Map.update(acc, key, [value], &(&1 ++ [value]))
    end)
  end
end
