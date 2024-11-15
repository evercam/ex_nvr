defmodule ExNVR.Repo.Migrations.AddIndexesToLprTable do
  use Ecto.Migration

  def change do
    create_if_not_exists unique_index("lpr_events", [:device_id, :capture_time])
  end
end
