defmodule ExNVR.Repo.Migrations.AddDeviceCredentialsField do
  use Ecto.Migration

  def up do
    alter table(:devices) do
      add :credentials, :map
    end

    execute """
      UPDATE devices SET credentials = json_set('{}',
      '$.username', json_extract(config, '$.username'),
      '$.password', json_extract(config, '$.password')),
      config = json_remove(config, '$.username', '$.password');
    """
    execute """
      UPDATE devices SET type=LOWER(type);
    """

  end

  def down do
    execute """
      UPDATE devices SET config = json_set('{}',
      '$.username', json_extract(credentials, '$.username'),
      '$.password', json_extract(credentials, '$.password'),
      '$.stream_uri', json_extract(config, '$.username'),
      '$.sub_stream_uri', json_extract(config, '$.password')
      );
    """
    execute """
      UPDATE devices SET type=UPPER(type);
    """
    execute """
      ALTER TABLE devices
      DROP COLUMN credentials;
    """
  end

end
