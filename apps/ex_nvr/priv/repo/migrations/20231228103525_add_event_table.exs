defmodule ExNVR.Repo.Migrations.AddEventTable do
  use Ecto.Migration

  def change do
    create table("events") do
      add :capture_time, :utc_datetime_usec, null: false
      add :plate_number, :string, null: false
      add :direction, :string, null: false
      add :type, :string, null: false

      add :device_id, references("devices"), null: false
    end
  end
end
