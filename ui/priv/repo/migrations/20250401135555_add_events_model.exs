defmodule ExNVR.Repo.Migrations.AddEventsModel do
  use Ecto.Migration

  def change do
    create table("events") do
      add :time, :utc_datetime_usec, default: fragment("CURRENT_TIMESTAMP")
      add :type, :string, null: false
      add :metadata, :map
      add :device_id, references("devices"), null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index("events", [:device_id])
    create index("events", [:type])
    create index("events", [:time])
  end
end
