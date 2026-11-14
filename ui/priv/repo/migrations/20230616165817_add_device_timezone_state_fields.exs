defmodule ExNVR.Repo.Migrations.AddDeviceTimezoneStateFields do
  use Ecto.Migration

  def change do
    alter table("devices") do
      add :timezone, :string, default: "UTC"
      add :state, :string, default: "recording"
    end
  end
end
