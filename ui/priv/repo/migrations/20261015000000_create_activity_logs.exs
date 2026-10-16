defmodule ExNVR.Repo.Migrations.CreateActivityLogs do
  use Ecto.Migration

  def change do
    # User actions only, what the system does on its own is stored as events.
    # No foreign keys on purpose: entries must outlive the devices and users they reference.
    create table("activity_logs") do
      add :time, :utc_datetime_usec, null: false
      add :category, :string, null: false
      add :action, :string, null: false
      add :severity, :string, null: false, default: "info"
      add :actor_type, :string, null: false
      add :actor_id, :string
      add :actor_label, :string
      add :device_id, :binary_id
      add :device_name, :string
      add :resource_type, :string
      add :resource_id, :string
      add :resource_label, :string
      add :message, :string, null: false
      add :metadata, :map, default: %{}
      add :source_ip, :string
    end

    create index("activity_logs", [:time])
    create index("activity_logs", [:category, :time])
    create index("activity_logs", [:severity, :time])
    create index("activity_logs", [:device_id, :time])
    create index("activity_logs", [:actor_id, :time])
  end
end
