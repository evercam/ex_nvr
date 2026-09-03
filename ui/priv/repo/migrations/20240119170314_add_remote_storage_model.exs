defmodule ExNVR.Repo.Migrations.AddRemoteStorageModel do
  use Ecto.Migration

  def change do
    create table("remote_storages") do
      add :name, :string, null: false, collate: :nocase
      add :type, :string, null: false
      add :url, :string
      add :config, :map

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:remote_storages, [:name], unique: true)
  end
end
