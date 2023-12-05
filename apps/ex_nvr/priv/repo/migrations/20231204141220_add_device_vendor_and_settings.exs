defmodule ExNVR.Repo.Migrations.AddDeviceVendor do
  use Ecto.Migration

  def up do
    alter table("devices") do
      add :vendor, :string, default: "hikvision"
      add :mac, :string, default: ""
      add :url, :string, default: ""
      add :model, :string, default: ""
    end
  end

  def down do
    alter table("devices") do
      remove :vendor
      remove :mac
      remove :url
      remove :model
    end
  end
end
