defmodule ExNVR.Repo.Migrations.AddRun do
  use Ecto.Migration

  def change do
    create table("runs") do
      add :start_date, :utc_datetime_usec, null: false
      add :end_date, :utc_datetime_usec, null: false
      add :active, :boolean, default: false

      add :device_id, references("devices"), null: false
    end

    create index("runs", [:device_id])
    create index("runs", [:start_date])
    create index("runs", [:end_date])
  end
end
