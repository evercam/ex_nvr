defmodule ExNVR.Repo.Migrations.AddStreamTypeToRecordings do
  use Ecto.Migration

  def change do
    alter table("recordings") do
      add :stream, :string, default: "high"
    end

    drop_if_exists index("recordings", [:device_id, :filename], unique: true)
    create_if_not_exists index("recordings", [:device_id, :stream])
    create_if_not_exists index("recordings", :start_date)
  end
end
