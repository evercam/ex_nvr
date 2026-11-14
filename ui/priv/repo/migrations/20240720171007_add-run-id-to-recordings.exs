defmodule :"Elixir.ExNVR.Repo.Migrations.Add-run-id-to-recordings" do
  use Ecto.Migration

  def change do
    alter table(:recordings) do
      add :run_id, references(:runs)
    end

    create index(:recordings, [:run_id])
  end
end
