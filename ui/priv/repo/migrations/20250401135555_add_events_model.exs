defmodule ExNVR.Repo.Migrations.AddEventsModel do
  use Ecto.Migration

  def change do
    create table("events") do
      add :event_time, :utc_datetime_usec, null: false, default: fragment("CURRENT_TIMESTAMP")
      add :event_type, :string, null: false
      add :event_data, :map
      add :device_id, references("devices"), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index("events", [:device_id])
    create index("events", [:event_type])
    create index("events", [:event_time])
  end
end
