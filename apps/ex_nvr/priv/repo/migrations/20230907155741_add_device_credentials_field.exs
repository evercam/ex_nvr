defmodule ExNVR.Repo.Migrations.AddDeviceCredentialsField do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add :credentials, :map
    end
  end
end
