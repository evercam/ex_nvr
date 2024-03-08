defmodule ExNVR.RemoteStorages.Store.S3 do
  @moduledoc false

  @behaviour ExNVR.RemoteStorages.Store

  alias ExAws.S3
  alias ExNVR.Model.{Device, Recording}
  alias ExNVR.Recordings

  @impl true
  @spec save_recording(Device.t(), Recording.t(), opts :: Keyword.t()) :: :ok | {:error, any()}
  def save_recording(device, recording, opts) do
    recording_path = Recordings.recording_path(device, recording)
    s3_path = String.trim(recording_path, ExNVR.Model.Device.base_dir(device))

    recording_path
    |> S3.Upload.stream_file()
    |> S3.upload(opts[:bucket], Path.join(device.id, s3_path), opts)
    |> ExAws.request(opts)
    |> case do
      {:ok, _resp} -> :ok
      error -> error
    end
  end

  @impl true
  def save_snapshot(device, snapshot, timestamp, opts) do
    key = build_snapshot_key(device.id, timestamp)

    opts
    |> Keyword.fetch!(:bucket)
    |> S3.put_object(key, snapshot, content_type: "image/jpeg")
    |> ExAws.request(opts)
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp build_snapshot_key(device_id, timestamp) do
    Calendar.strftime(timestamp, "ex_nvr/#{device_id}/%Y/%m/%d/%H/%M_%S_000.jpeg")
  end
end
