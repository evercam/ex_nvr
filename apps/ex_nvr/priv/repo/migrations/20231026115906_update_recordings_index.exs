defmodule ExNVR.Repo.Migrations.UpdateRecordingsIndex do
  use Ecto.Migration

  def change do
    drop index("recordings", [:filename], unique: true)
    create index("recordings", [:device_id, :filename], unique: true)
  end
end
