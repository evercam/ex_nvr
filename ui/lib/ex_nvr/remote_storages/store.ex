defmodule ExNVR.RemoteStorages.Store do
  @moduledoc false

  alias ExNVR.Model.{Device, Recording}
  alias ExNVR.RemoteStorages.Store.{HTTP, S3}

  @callback save_recording(Device.t(), Recording.t(), opts :: Keyword.t()) ::
              :ok | {:error, any()}

  @callback save_snapshot(
              Device.t(),
              snapshot :: binary(),
              timestamp :: DateTime.t(),
              opts :: Keyword.t()
            ) :: :ok | {:error, any()}

  def save_snapshot(remote_storage, device, snapshot, timestamp, opts),
    do: impl(remote_storage).save_snapshot(device, snapshot, timestamp, opts)

  defp impl(%{type: :s3}), do: S3
  defp impl(%{type: :http}), do: HTTP
end
