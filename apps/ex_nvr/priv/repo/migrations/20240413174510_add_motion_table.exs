defmodule ExNVR.Repo.Migrations.AddMotionTable do
  use Ecto.Migration

  def change do
    create table("motions") do
      add :label, :string, null: false, size: 150
      add :dimentions, :map
      add :time, :utc_datetime_usec, null: false
      add :device_id, references("devices"), null: false

      timestamps(type: :utc_datetime_usec)
    end
  end
end
