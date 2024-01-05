defmodule ExNVR.Repo.Migrations.AddEventTable do
  use Ecto.Migration

  def change do
    create table("lpr_events") do
      add :capture_time, :utc_datetime_usec, null: false
      add :plate_number, :string, null: false
      add :direction, :string, null: false
      add :list_type, :string, null: false
      add :confidence, :float, null: false
      add :vehicle_type, :string, null: false
      add :vehicle_color, :string, null: false
      add :plate_color, :string, null: false
      add :bounding_box, :map, null: false

      add :device_id, references("devices"), null: false
      timestamps(type: :utc_datetime_usec)
    end
  end
end
