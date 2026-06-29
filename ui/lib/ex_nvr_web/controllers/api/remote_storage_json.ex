defmodule ExNVRWeb.API.RemoteStorageJSON do
  @moduledoc false

  @spec show(map()) :: map()
  def show(%{remote_storage: remote_storage}) do
    serialize_remote_storage(remote_storage)
  end

  def list(%{remote_storages: remote_storages}) do
    Enum.map(remote_storages, &serialize_remote_storage/1)
  end

  defp serialize_remote_storage(remote_storage) do
    remote_storage
    |> Map.from_struct()
    |> Map.take([:id, :name, :type, :url])
  end
end
