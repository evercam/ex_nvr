defmodule ExNVR.Repo.Migrations.AddStreamTypeToRecordings do
  use Ecto.Migration

  def up do
    alter table("recordings") do
      add :stream, :string, default: "high"
    end

    alter table("runs") do
      add :stream, :string, default: "high"
    end

    alter table("devices") do
      add :storage_config, :map
    end

    drop_if_exists index("recordings", [:device_id, :filename], unique: true)
    create_if_not_exists index("recordings", [:device_id, :stream])
    create_if_not_exists index("recordings", :start_date)

    drop_if_exists index("runs", [:device_id])
    create_if_not_exists index("runs", [:device_id, :stream])

    execute """
    UPDATE devices set storage_config = json_set('{}', '$.address', json_extract(settings, '$.storage_address'),
                          '$.full_drive_threshold', json_extract(settings, '$.override_on_full_disk_threshold'),
                          '$.full_drive_action', case when json_extract(settings, '$.override_on_full_disk') = 1 then 'overwrite' else 'nothing' end),
                       settings = json_remove(settings, '$.storage_address', '$.override_on_full_disk', '$.override_on_full_disk_threshold');
    """
  end

  def down do
    execute """
    UPDATE devices set settings = json_set(settings, '$.storage_address', json_extract(storage_config, '$.address'),
                      '$.override_on_full_disk', case when json_extract(storage_config, '$.full_drive_action') != 'nothing' then 1 else 0 end,
                      '$.override_on_full_disk_threshold', json_extract(storage_config, '$.full_drive_threshold'))
    """

    drop_if_exists index("recordings", [:device_id, :stream])
    drop_if_exists index("recordings", :start_date)
    create_if_not_exists index("recordings", [:device_id, :filename], unique: true)

    drop_if_exists index("runs", [:device_id, :stream])
    create_if_not_exists index("runs", [:device_id])

    alter table("recordings") do
      remove :stream, :string
    end

    alter table("runs") do
      remove :stream, :string
    end

    alter table("devices") do
      remove :storage_config, :map
    end
  end
end
