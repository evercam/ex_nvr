defmodule ExNVR.RemoteStorages.Store do
  @moduledoc false

  alias ExNVR.Model.{Device, Recording, RemoteStorage}
  alias ExNVR.RemoteStorages.Store.{HTTP, S3}

  @callback save_recording(Device.t(), Recording.t(), opts :: Keyword.t()) ::
              :ok | {:error, any()}

  @callback save_snapshot(RemoteStorage.t(), binary(), DateTime.t(), binary()) ::
              :ok | {:error, any()}

  def save_snapshot(remote_storage, device_id, timestamp, snapshot),
    do: impl(remote_storage).save_snapshot(remote_storage, device_id, timestamp, snapshot)

  defp impl(%{type: :s3}), do: S3
  defp impl(%{type: :http}), do: HTTP
end
