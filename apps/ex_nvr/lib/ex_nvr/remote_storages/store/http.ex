defmodule ExNVR.RemoteStorages.Store.HTTP do
  @moduledoc false

  @behaviour ExNVR.RemoteStorages.Store

  alias ExNVR.Model.{Device, Recording}
  alias ExNVR.Recordings

  @type http_opts :: [
          url: binary(),
          auth_type: :basic | :bearer | nil,
          username: binary(),
          password: binary(),
          token: binary()
        ]

  @impl true
  @spec save_recording(Device.t(), Recording.t(), http_opts()) :: :ok | {:error, any()}
  def save_recording(device, recording, opts) do
    recording_path = Recordings.recording_path(device, recording)

    file_part =
      Multipart.Part.file_field(recording_path, "file", [],
        filename: Path.basename(recording_path)
      )

    multipart =
      Multipart.new()
      |> Multipart.add_part(json_part(%{device_id: device.id, start_date: recording.start_date}))
      |> Multipart.add_part(file_part)

    resp =
      Req.post(opts[:url],
        auth: auth_from_opts(opts),
        headers: headers_from_multipart(multipart),
        body: Multipart.body_stream(multipart)
      )

    case resp do
      {:ok, %{status: status}} when status >= 200 and status < 300 -> :ok
      {:ok, resp} -> {:error, resp}
      error -> error
    end
  end

  @impl true
  def save_snapshot(%{url: url, http_config: http_config}, device_id, timestamp, snapshot) do
    filename = Calendar.strftime(timestamp, "#{device_id}_%Y-%m-%dT%H:%M:%S:000.jpeg")

    file_part =
      Multipart.Part.file_content_field("", snapshot, "file", [], filename: filename)

    multipart =
      Multipart.new()
      |> Multipart.add_part(json_part(%{device_id: device_id, timestamp: timestamp}))
      |> Multipart.add_part(file_part)

    opts = add_auth_type(http_config)

    resp =
      Req.post(url,
        auth: auth_from_opts(opts),
        headers: headers_from_multipart(multipart),
        body: Multipart.body_stream(multipart)
      )

    case resp do
      {:ok, %{status: status}} when status >= 200 and status < 300 -> :ok
      {:ok, resp} -> {:error, resp}
      error -> error
    end
  end

  defp add_auth_type(%{username: username, password: password, token: token} = http_config) do
    cond do
      not is_nil(token) ->
        Map.put(http_config, :auth_type, :bearer) |> Map.to_list()

      not is_nil(username) && not is_nil(password) ->
        Map.put(http_config, :auth_type, :basic) |> Map.to_list()

      true ->
        Map.to_list(http_config)
    end
  end

  defp json_part(data) do
    data
    |> Jason.encode!()
    |> Multipart.Part.text_field("metadata", [{"Content-Type", "application/json"}])
  end

  defp auth_from_opts(opts) do
    case opts[:auth_type] do
      :bearer -> {:bearer, opts[:token]}
      :basic -> {:basic, "#{opts[:username]}:#{opts[:password]}"}
      _other -> nil
    end
  end

  defp headers_from_multipart(multipart) do
    content_length = Multipart.content_length(multipart)
    content_type = Multipart.content_type(multipart, "multipart/form-data")

    [
      {"Content-Length", to_string(content_length)},
      {"Content-Type", content_type}
    ]
  end
end
