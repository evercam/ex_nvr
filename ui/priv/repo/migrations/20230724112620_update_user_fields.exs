defmodule ExNVR.Repo.Migrations.UpdateUserFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :first_name, :string
      add :last_name, :string
      add :username, :string, collate: :nocase
      add :language, :string
    end

    create unique_index(:users, [:username], unique: true)
  end
end
