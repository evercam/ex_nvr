defmodule ExNVR.Repo.Migrations.AddDeviceModel do
  use Ecto.Migration

  def change do
    create table("devices", primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false, size: 50
      add :type, :string, null: false
      add :config, :map

      timestamps(type: :utc_datetime_usec)
    end
  end
end
