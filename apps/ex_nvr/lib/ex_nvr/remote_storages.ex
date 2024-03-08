defmodule ExNVR.RemoteStorages do
  @moduledoc """
  Context to manipulate remote storages
  """

  require Logger

  import Ecto.Query

  alias ExNVR.RemoteStorage
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

  @spec get(number()) :: Device.t() | nil
  def get(id), do: Repo.get(RemoteStorage, id)

  @spec get!(number()) :: RemoteStorage.t()
  def get!(id), do: Repo.get!(RemoteStorage, id)

  @spec get_by(Keyword.t() | map()) :: Ecto.Schema.t() | term() | nil
  def get_by(clauses) do
    Repo.get_by(RemoteStorage, clauses)
  end

  @spec list() :: [RemoteStorage.t()]
  def list(), do: Repo.all(RemoteStorage |> order_by([rs], rs.inserted_at))

  @spec delete(RemoteStorage.t()) :: :ok | {:error, Ecto.Changeset.t()}
  def delete(%RemoteStorage{} = remote_storage) do
    case Repo.delete(remote_storage) do
      {:ok, _deleted_remote_storage} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  def count_remote_storages(), do: Repo.aggregate(RemoteStorage, :count)

  @spec change_remote_storage_creation(RemoteStorage.t(), map()) :: Ecto.Changeset.t()
  def change_remote_storage_creation(%RemoteStorage{} = remote_storage, attrs \\ %{}) do
    RemoteStorage.create_changeset(remote_storage, attrs)
  end

  @spec change_remote_storage_update(RemoteStorage.t(), map()) :: Ecto.Changeset.t()
  def change_remote_storage_update(%RemoteStorage{} = remote_storage, attrs \\ %{}) do
    RemoteStorage.update_changeset(remote_storage, attrs)
  end
end
