defmodule ExNVR.Repo.Migrations.AddEventTable do
  use Ecto.Migration

  def change do
    create table("lpr_events") do
      add :capture_time, :utc_datetime_usec, null: false
      add :plate_number, :string, null: false
      add :direction, :string
      add :list_type, :string
      add :confidence, :float
      add :vehicle_type, :string
      add :vehicle_color, :string
      add :plate_color, :string
      add :bounding_box, :map

      add :device_id, references("devices"), null: false
      timestamps(type: :utc_datetime_usec)
    end
  end
end
