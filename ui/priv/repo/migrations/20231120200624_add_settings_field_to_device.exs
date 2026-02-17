defmodule ExNVR.Repo.Migrations.AddSettingsFieldToDevice do
  use Ecto.Migration

  def change do
    alter table("devices") do
      add :settings, :map, default: %{}
    end

    drop index("recordings", [:filename], unique: true)
    create index("recordings", [:device_id, :filename], unique: true)
  end
end
