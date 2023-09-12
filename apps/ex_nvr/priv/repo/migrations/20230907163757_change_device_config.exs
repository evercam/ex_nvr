defmodule ExNVR.Repo.Migrations.ChangeDeviceConfig do
  use Ecto.Migration

  import Ecto.Query

  alias ExNVR.Repo
  alias Ecto.Changeset

  def up do
    # Migrate data from old schema to new schema
    Repo.all(ExNVR.Model.Device)
    |> Enum.each(&migrate_device/1)
  end

  def down do
    # Rollback the changes if needed
    # Migrate data from new schema to old schema
    Repo.all(ExNVR.Model.Device)
    |> Enum.each(&migrate_to_old_schema/1)
  end

  defp migrate_device(%ExNVR.Model.Device{type: :IP} = old_device) do
    new_device_params = %{
      name: old_device.name,
      type: :IP,
      timezone: old_device.timezone,
      state: old_device.state,
      credentials: %{
        username: old_device.stream_config.username,
        password: old_device.stream_config.password
      },
      stream_config: %{
        stream_uri: old_device.stream_config.stream_uri,
        sub_stream_uri: old_device.stream_config.sub_stream_uri,
        location: nil
      }
    }

    Repo.update(Changeset.change(old_device, new_device_params))
  end

  defp migrate_device(_), do: nil

  defp migrate_to_old_schema(%ExNVR.Model.Device{type: :IP} = old_device) do
    # For devices with type "IP", create a new device with the old schema
    new_device_params = %{
      name: old_device.name,
      type: :IP,
      timezone: old_device.timezone,
      state: old_device.state,
      ip_camera_config: %{
        stream_uri: old_device.stream_config.stream_uri,
        sub_stream_uri: old_device.stream_config.sub_stream_uri,
        username: old_device.credentials.username,
        password: old_device.credentials.password
      }
    }

    Repo.update(Changeset.change(old_device, new_device_params))
  end

  defp migrate_to_old_schema(%ExNVR.Model.Device{type: :FILE} = old_device) do
    # For devices with type "FILE", create a new device with the old schema
    new_device_params = %{
      name: old_device.name,
      type: :IP,
      timezone: old_device.timezone,
      state: old_device.state,
      ip_camera_config: %{
        stream_uri: old_device.stream_config.location,
        sub_stream_uri: nil,
        username: nil,
        password: nil
      }
    }

    Repo.update(Changeset.change(old_device, new_device_params))
  end

  defp migrate_to_old_schema(_), do: nil
end
