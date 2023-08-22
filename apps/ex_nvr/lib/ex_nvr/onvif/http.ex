defmodule ExNVR.Onvif.Http do
  @moduledoc false

  import Mockery.Macro

  @onvif_path Path.join([Application.app_dir(:ex_nvr), "priv", "onvif"])
  @device_model_path Path.join(@onvif_path, "devicemgmt.wsdl")

  @spec call(binary(), binary(), map(), Keyword.t()) ::
          {:ok, Soap.Response.t()} | {:error, term()}
  def call(url, operation, body, opts \\ []) do
    wsdl = init_wsdl_model_with_url(@device_model_path, url)

    username = opts[:username] || ""
    password = opts[:password] || ""

    if username == "" or password == "" do
      mockable(Soap).call(wsdl, operation, body)
    else
      http_headers = [{"authorization", Base.encode64(username <> ":" <> password)}]
      result = mockable(Soap).call(wsdl, operation, body, http_headers)

      with {:ok, %{status_code: 401} = resp} <- result,
           digest_opts when is_map(digest_opts) <- digest_auth_opts(resp, opts),
           http_headers <- [{"Authorization", encode_digest(digest_opts)}] do
        mockable(Soap).call(wsdl, operation, body, http_headers)
      else
        _other -> result
      end
    end
  end

  @spec encode_digest(map()) :: String.t()
  def encode_digest(opts) do
    uri = "/onvif/device_service"
    ha1 = md5([opts.username, opts.realm, opts.password])
    ha2 = md5(["POST", "/onvif/device_service"])
    response = md5([ha1, opts.nonce, ha2])

    Enum.join(
      [
        "Digest",
        ~s(username="#{opts.username}",),
        ~s(realm="#{opts.realm}",),
        ~s(nonce="#{opts.nonce}",),
        ~s(uri="#{uri}",),
        ~s(response="#{response}")
      ],
      " "
    )
  end

  @spec md5([String.t()]) :: String.t()
  def md5(value) do
    value
    |> Enum.join(":")
    |> IO.iodata_to_binary()
    |> :erlang.md5()
    |> Base.encode16(case: :lower)
  end

  defp digest_auth_opts(%{headers: headers}, opts) do
    case Map.fetch(Map.new(headers), "WWW-Authenticate") do
      {:ok, "Digest " <> digest} ->
        [_match, nonce] = Regex.run(~r/nonce=\"(?<nonce>.*)\"/U, digest)
        [_match, realm] = Regex.run(~r/realm=\"(?<realm>.*)\"/U, digest)
        %{nonce: nonce, realm: realm, username: opts[:username], password: opts[:password]}

      _other ->
        nil
    end
  end

  defp init_wsdl_model_with_url(path, url) do
    {:ok, model} = Soap.init_model(path)
    %{model | endpoint: url}
  end
end
