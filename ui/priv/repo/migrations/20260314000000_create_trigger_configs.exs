defmodule ExNVR.Repo.Migrations.CreateTriggerConfigs do
  use Ecto.Migration

  def change do
    create table(:trigger_configs) do
      add :name, :string, null: false
      add :enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:trigger_configs, [:name])

    create table(:trigger_source_configs) do
      add :trigger_config_id, references(:trigger_configs, on_delete: :delete_all), null: false
      add :source_type, :string, null: false
      add :config, :map, default: %{}, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:trigger_source_configs, [:trigger_config_id])

    create table(:trigger_target_configs) do
      add :trigger_config_id, references(:trigger_configs, on_delete: :delete_all), null: false
      add :target_type, :string, null: false
      add :config, :map, default: %{}, null: false
      add :enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:trigger_target_configs, [:trigger_config_id])

    create table(:devices_trigger_configs, primary_key: false) do
      add :device_id, references(:devices, type: :binary_id, on_delete: :delete_all), null: false
      add :trigger_config_id, references(:trigger_configs, on_delete: :delete_all), null: false
    end

    create unique_index(:devices_trigger_configs, [:device_id, :trigger_config_id])
  end
end
