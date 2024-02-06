defmodule ExNVR.S3 do
  alias ExAws.S3

  def save_snapshot(%{url: url, s3_config: s3_config}, device_id, timestamp, snapshot) do
    key = key_from_timestamp(device_id, timestamp)

    config = add_url_to_config(Map.from_struct(s3_config), url) |> Map.to_list()

    config
    |> Keyword.fetch!(:bucket)
    |> S3.put_object(key, snapshot, content_type: "image/jpeg")
    |> ExAws.request(config)
    |> case do
      {:ok, _} ->
        :ok

      error ->
        error
    end
  end

  defp key_from_timestamp(device_id, timestamp) do
    Calendar.strftime(timestamp, "#{device_id}/%Y/%m/%d/%H/%M_%S_000.jpg")
  end

  defp add_url_to_config(config, nil), do: config

  defp add_url_to_config(config, url) do
    uri = URI.parse(url)

    Map.merge(config, %{scheme: uri.scheme, host: uri.host, port: uri.port})
  end
end
