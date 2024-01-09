defmodule ExNVR.RemoteStoragesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ExNVR.RemoteStorages` context.
  """

  alias ExNVR.Model.RemoteStorage

  @spec valid_remote_storage_name() :: binary()
  def valid_remote_storage_name(),
    do: "RemoteStorage_#{System.unique_integer([:monotonic, :positive])}"

  @spec valid_remote_storage_attributes(map(), binary()) :: map()
  def valid_remote_storage_attributes(attrs \\ %{}, type \\ "s3") do
    {config, attrs} = Map.pop(attrs, :config, %{})

    config = build_config(config, type)

    Enum.into(attrs, %{
      name: valid_remote_storage_name(),
      type: type,
      config: config
    })
  end

  @spec remote_storage_fixture(map(), binary()) :: RemoteStorage.t()
  def remote_storage_fixture(attrs \\ %{}, remote_storage_type \\ "s3") do
    {:ok, remote_storage} =
      attrs
      |> valid_remote_storage_attributes(remote_storage_type)
      |> ExNVR.RemoteStorages.create()

    remote_storage
  end

  defp build_config(stream_config, "s3") do
    Enum.into(stream_config, %{
      url: "https://example#{System.unique_integer()}",
      bucket: "remote-storage-bucket",
      region: "us-east-1",
      access_key_id: :crypto.strong_rand_bytes(16) |> Base.encode16(),
      secret_access_key: :crypto.strong_rand_bytes(16) |> Base.encode16()
    })
  end

  defp build_config(stream_config, "seaweedfs") do
    Enum.into(stream_config, %{
      url: "https://example#{System.unique_integer()}",
      token: :crypto.strong_rand_bytes(16) |> Base.encode64()
    })
  end
end
