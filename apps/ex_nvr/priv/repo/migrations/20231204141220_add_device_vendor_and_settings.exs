defmodule ExNVR.Repo.Migrations.AddDeviceVendor do
  use Ecto.Migration

  def change do
    alter table("devices") do
      add :vendor, :string
      add :mac, :string
      add :url, :string
      add :model, :string
    end
  end
end
