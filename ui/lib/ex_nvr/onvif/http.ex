defmodule ExNVR.Onvif.Http do
  @moduledoc false

  import Mockery.Macro

  alias ExNVR.HTTP

  @onvif_path Path.join([Application.app_dir(:ex_nvr), "priv", "onvif"])
  @device_wsdl Soap.init_model(Path.join(@onvif_path, "devicemgmt.wsdl")) |> elem(1)
  @media_wsdl Soap.init_model(Path.join(@onvif_path, "media2.wsdl")) |> elem(1)

  @spec call(binary(), binary(), map(), Keyword.t()) ::
          {:ok, Soap.Response.t()} | {:error, term()}
  def call(url, operation, body, opts \\ []) do
    wsdl = get_model(opts[:model] || :device, url)

    username = opts[:username] || ""
    password = opts[:password] || ""
    opts = opts ++ [method: :post, url: url]

    if username == "" or password == "" do
      mockable(Soap).call(wsdl, operation, body)
    else
      http_headers = [{"Authorization", "Basic " <> Base.encode64(username <> ":" <> password)}]
      result = mockable(Soap).call(wsdl, operation, body, http_headers)

      with {:ok, %{status_code: 401} = resp} <- result,
           {:ok, digest_auth} <- HTTP.build_digest_auth(resp, opts) do
        mockable(Soap).call(wsdl, operation, body, [{"Authorization", digest_auth}])
      else
        _other -> result
      end
    end
  end

  defp get_model(:media, endpoint), do: %{@media_wsdl | endpoint: endpoint}
  defp get_model(:device, endpoint), do: %{@device_wsdl | endpoint: endpoint}
end
