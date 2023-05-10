defmodule ExNVR.Repo.Migrations.CreateRecordingsTable do
  use Ecto.Migration

  def change do
    create table("recordings") do
      add :start_date, :utc_datetime_usec
      add :end_date, :utc_datetime_usec
      add :filename, :string
    end

    create index("recordings", [:filename], unique: true)
  end
end
