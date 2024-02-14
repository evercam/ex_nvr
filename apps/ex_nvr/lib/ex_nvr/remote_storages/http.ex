defmodule ExNVR.RemoteStorages.Http do
  @moduledoc false

  alias ExNVR.HTTP
  alias Tesla.Multipart
  alias ExNVR.RemoteStorages.Client

  @behaviour Client

  @impl Client
  def save_snapshot(%{url: url, http_config: http_config}, device_id, timestamp, snapshot) do
    {headers, body} = build_request(http_config, device_id, timestamp, snapshot)

    HTTP.post(url, headers, body)
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp build_request(config, device_id, timestamp, snapshot) do
    authorization_header = build_authorization_header(config)

    filename = Calendar.strftime(timestamp, "#{device_id}_%Y-%m-%d_%H:%M:%S:000.jpeg")

    multipart =
      Multipart.add_file_content(Multipart.new(), snapshot, filename,
        headers: [{"content-type", "image/jpeg"}]
      )

    headers = authorization_header ++ Multipart.headers(multipart)
    body = Enum.join(Multipart.body(multipart), "")

    {headers, body}
  end

  defp build_authorization_header(%{username: username, password: password, token: token}) do
    cond do
      not is_nil(token) ->
        [{"Authorization", "Bearer " <> token}]

      not is_nil(username) && not is_nil(password) ->
        [{"Authorization", "Basic " <> Base.encode64(username <> ":" <> password)}]

      true ->
        []
    end
  end
end
