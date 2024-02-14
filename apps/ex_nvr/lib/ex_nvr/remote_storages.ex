defmodule ExNVR.RemoteStorages do
  @moduledoc """
  Context to manipulate remote storages
  """

  require Logger

  import Ecto.Query

  alias ExNVR.{RemoteStorage}
  alias ExNVR.Repo

  @spec create(map()) :: {:ok, RemoteStorage.t()} | {:error, Ecto.Changeset.t()}
  def create(params) do
    params
    |> RemoteStorage.create_changeset()
    |> Repo.insert()
  end

  @spec update(RemoteStorage.t(), map()) ::
          {:ok, RemoteStorage.t()} | {:error, Ecto.Changeset.t()}
  def update(%RemoteStorage{} = remote_storage, params) do
    remote_storage
    |> RemoteStorage.update_changeset(params)
    |> Repo.update()
  end

  @spec get!(number()) :: RemoteStorage.t()
  def get!(id), do: Repo.get!(RemoteStorage, id)

  @spec list() :: [RemoteStorage.t()]
  def list(), do: Repo.all(RemoteStorage |> order_by([rs], rs.inserted_at))

  @spec delete(RemoteStorage.t()) :: {:ok, RemoteStorage.t()} | {:error, Ecto.Changeset.t()}
  def delete(%RemoteStorage{} = remote_storage) do
    Repo.delete(remote_storage)
  end

  @spec change_remote_storage_creation(RemoteStorage.t(), map()) :: Ecto.Changeset.t()
  def change_remote_storage_creation(%RemoteStorage{} = remote_storage, attrs \\ %{}) do
    RemoteStorage.create_changeset(remote_storage, attrs)
  end

  @spec change_remote_storage_update(RemoteStorage.t(), map()) :: Ecto.Changeset.t()
  def change_remote_storage_update(%RemoteStorage{} = remote_storage, attrs \\ %{}) do
    RemoteStorage.update_changeset(remote_storage, attrs)
  end
end
