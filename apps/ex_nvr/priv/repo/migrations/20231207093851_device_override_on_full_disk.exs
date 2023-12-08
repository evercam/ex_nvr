defmodule ExNVR.Repo.Migrations.DeviceOverrideOnFullDisk do
  use Ecto.Migration

  def up do
    execute """
      UPDATE devices SET settings = json_set('{}',
      '$.generate_bif',
        CASE
          WHEN json_extract(settings, '$.generate_bif') = 'true' THEN json('false')
          ELSE json('true')
        END,
      '$.storage_address', json_extract(settings, '$.storage_address'),
      '$.override_on_full_disk', json('false'),
      '$.override_on_full_disk_threshold', 90.0
      );
    """
  end

  def down do
    execute """
      UPDATE devices SET settings = json_set('{}',
      '$.generate_bif',
        CASE
          WHEN json_extract(settings, '$.generate_bif') = 'true' THEN json('false')
          ELSE json('true')
        END,
      '$.storage_address', json_extract(settings, '$.storage_address')
      );
    """
  end
end
