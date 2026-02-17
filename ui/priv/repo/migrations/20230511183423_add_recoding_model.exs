defmodule ExNVR.Repo.Migrations.AddRecodingModel do
  use Ecto.Migration

  def change do
    create table("recordings") do
      add :start_date, :utc_datetime_usec, null: false
      add :end_date, :utc_datetime_usec, null: false
      add :filename, :string, null: false

      add :device_id, references("devices"), null: false
    end

    create index("recordings", [:filename], unique: true)
  end
end
