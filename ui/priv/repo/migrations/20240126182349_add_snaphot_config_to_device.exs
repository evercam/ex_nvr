defmodule ExNVR.Repo.Migrations.AddSnaphotConfigToDevice do
  use Ecto.Migration

  def change do
    alter table("devices") do
      add :snapshot_config, :map
    end
  end
end
