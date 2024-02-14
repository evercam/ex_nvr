defmodule ExNVR.RemoteStorages.Client do
  @moduledoc """
  A remote storage client behaviour.

  Contains function to upload a snapshot to a remote storage
  function.
  """

  alias ExNVR.RemoteStorages.{Http, S3}

  @type remote_storage :: ExNVR.Model.RemoteStorage.t()
  @type device_id :: binary()
  @type timestamp :: timestamp()
  @type snapshot :: binary()

  @callback save_snapshot(remote_storage(), device_id(), timestamp(), snapshot()) ::
              :ok | {:error, term()}

  def save_snapshot(remote_storage, device_id, timestamp, snapshot),
    do: impl(remote_storage).save_snapshot(remote_storage, device_id, timestamp, snapshot)

  defp impl(%{type: :s3}), do: S3
  defp impl(%{type: :http}), do: Http
end
