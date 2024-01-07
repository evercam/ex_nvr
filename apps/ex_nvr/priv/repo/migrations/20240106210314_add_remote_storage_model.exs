defmodule ExNVR.Repo.Migrations.AddRemoteStorageModel do
  use Ecto.Migration

  def change do
    create table("remote_storages") do
      add :name, :string, null: false, size: 50
      add :type, :string, null: false
      add :config, :map

      timestamps(type: :utc_datetime_usec)
    end
  end
end
