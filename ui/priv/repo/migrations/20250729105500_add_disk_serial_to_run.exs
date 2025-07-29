defmodule ExNVR.Repo.Migrations.AddDiskSerialToRun do
  use Ecto.Migration

  def change do
    alter table :runs do
      add :disk_serial, :string
    end
  end
end
