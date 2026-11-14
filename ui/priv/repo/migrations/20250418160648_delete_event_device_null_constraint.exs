defmodule ExNVR.Repo.Migrations.DeleteEventDeviceNullConstraint do
  use Ecto.Migration

  def change do
    drop_if_exists index("events", [:device_id])

    alter table("events") do
      remove :device_id
      add :device_id, references("devices"), null: true
    end

    create index("events", [:device_id])
  end
end
