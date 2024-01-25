defmodule ExNVR.Repo.Migrations.AddDiskSystemInformation do
  use Ecto.Migration

  def change do
    create table("storage_devices") do
      add :vendor, :string
      add :model, :string, null: false
      add :serial, :string, null: false
      add :type, :string
      add :size, :integer, null: false
      add :transport, :string
      add :hotplug, :boolean

      timestamps(type: :utc_datetime_usec)
    end

    alter table("runs") do
      add :disk_id, references("storage_devices")
    end
  end
end
