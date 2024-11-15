defmodule ExNVR.Repo.Migrations.AddEventTable do
  use Ecto.Migration

  def change do
    create table("lpr_events") do
      add :capture_time, :utc_datetime_usec, null: false
      add :plate_number, :string, null: false
      add :direction, :string
      add :list_type, :string
      add :metadata, :map

      add :device_id, references("devices"), null: false
      timestamps(type: :utc_datetime_usec)
    end
  end
end
