defmodule ExNVR.Repo.Migrations.CreateExportJobs do
  use Ecto.Migration

  def change do
    # Index of export jobs so they can be listed; each job's state lives in
    # the manifest inside its destination directory.
    create table(:export_jobs) do
      add :dest_dir, :string, null: false
      add :device_id, :string, null: false
      add :kind, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:export_jobs, [:dest_dir])
    create index(:export_jobs, [:updated_at])
  end
end
