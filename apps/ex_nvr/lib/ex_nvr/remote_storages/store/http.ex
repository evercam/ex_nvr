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

    json_part =
      %{device_id: device.id, start_date: recording.start_date}
      |> Jason.encode!()
      |> Multipart.Part.text_field("metadata", [{"Content-Type", "application/json"}])

    file_part =
      Multipart.Part.file_field(recording_path, "file", [],
        filename: Path.basename(recording_path)
      )

    multipart =
      Multipart.new()
      |> Multipart.add_part(json_part)
      |> Multipart.add_part(file_part)

    content_length = Multipart.content_length(multipart)
    content_type = Multipart.content_type(multipart, "multipart/form-data")

    headers = [
      {"Content-Length", to_string(content_length)},
      {"Content-Type", content_type}
    ]

    resp =
      Req.post(opts[:url],
        auth: auth_from_opts(opts),
        headers: headers,
        body: Multipart.body_stream(multipart)
      )

    case resp do
      {:ok, %{state: 200}} -> :ok
      {:ok, resp} -> {:error, resp}
      error -> error
    end
  end

  defp auth_from_opts(opts) do
    case opts[:auth_type] do
      :bearer -> {:bearer, opts[:token]}
      :basic -> {:basic, "#{opts[:username]}:#{opts[:password]}"}
      _other -> nil
    end
  end
end
