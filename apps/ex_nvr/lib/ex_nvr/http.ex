defmodule ExNVR.HTTP do
  @moduledoc false

  import Mockery.Macro

  @spec get(binary(), Keyword.t()) ::
          {:ok, Finch.Response.t()} | {:error, term()}
  def get(url, opts \\ []) do
    username = opts[:username] || ""
    password = opts[:password] || ""
    finch = mockable(Finch)

    if username == "" or password == "" do
      finch.build(:get, url) |> finch.request(ExNVR.Finch)
    else
      http_headers = [{"Authorization", "Basic " <> Base.encode64(username <> ":" <> password)}]
      result = finch.build(:get, url, http_headers) |> finch.request(ExNVR.Finch)

      with {:ok, %{status: 401} = resp} <- result,
           digest_opts when is_map(digest_opts) <- digest_auth_opts(resp, opts),
           digest_opts <- Map.merge(digest_opts, %{method: "GET", uri: URI.parse(url).path}),
           http_headers <- [{"Authorization", encode_digest(digest_opts)}] do
        finch.build(:get, url, http_headers) |> finch.request(ExNVR.Finch)
      else
        _other ->
          result
      end
    end
  end

  @spec digest_auth_opts(map(), map(), binary()) :: map() | nil
  def digest_auth_opts(%{headers: headers}, opts, auth_method_header \\ "www-authenticate") do
    case Map.fetch(Map.new(headers), auth_method_header) do
      {:ok, "Digest " <> digest} ->
        [_match, nonce] = Regex.run(~r/nonce=\"(?<nonce>.*)\"/U, digest)
        [_match, realm] = Regex.run(~r/realm=\"(?<realm>.*)\"/U, digest)
        %{nonce: nonce, realm: realm, username: opts[:username], password: opts[:password]}

      _other ->
        nil
    end
  end

  @spec encode_digest(map()) :: String.t()
  def encode_digest(opts) do
    ha1 = md5([opts.username, opts.realm, opts.password])
    ha2 = md5([opts.method, opts.uri])
    response = md5([ha1, opts.nonce, ha2])

    Enum.join(
      [
        "Digest",
        ~s(username="#{opts.username}",),
        ~s(realm="#{opts.realm}",),
        ~s(nonce="#{opts.nonce}",),
        ~s(uri="#{opts.uri}",),
        ~s(response="#{response}")
      ],
      " "
    )
  end

  defp md5(value) do
    value
    |> Enum.join(":")
    |> IO.iodata_to_binary()
    |> :erlang.md5()
    |> Base.encode16(case: :lower)
  end
end
