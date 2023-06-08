defmodule ExNVR.DevicesTest do
  use ExNVR.DataCase

  alias ExNVR.Devices
  alias ExNVR.Model.Device

  import ExNVR.DevicesFixtures

  describe "list_devices/1" do
    test "returns empty list if no device exists" do
      assert Enum.empty?(Devices.list())
    end

    test "returns all the devices" do
      [%{id: device_one_id}, %{id: device_two_id}] = [device_fixture(), device_fixture()]
      assert Enum.sort([device_one_id, device_two_id]) == Devices.list() |> Enum.map(& &1.id)
    end
  end

  describe "change_user_creation/1" do
    test "returns changeset" do
      assert %Ecto.Changeset{} = changeset = Devices.change_device_creation(%Device{})
      assert changeset.required == [:name, :type]
    end

    test "requires IP camera config to be set when type is IP" do
      name = "Camera 1"

      assert %Ecto.Changeset{} =
               changeset =
               Devices.change_device_creation(
                 %Device{},
                 valid_device_attributes(name: name, type: "IP")
               )

      assert changeset.required == [:ip_camera_config, :name, :type]
    end

    test "allows fields to be set" do
      name = "Camera 1"

      ip_camera_config = %{
        stream_uri: valid_rtsp_url()
      }

      assert %Ecto.Changeset{} =
               changeset =
               Devices.change_device_creation(
                 %Device{},
                 valid_device_attributes(
                   name: name,
                   type: "IP",
                   ip_camera_config: ip_camera_config
                 )
               )

      assert changeset.valid?
      assert get_change(changeset, :name) == name
      assert get_change(changeset, :type) == :IP

      assert %Ecto.Changeset{} = config_changeset = get_change(changeset, :ip_camera_config)
      assert get_change(config_changeset, :stream_uri) == ip_camera_config.stream_uri
    end
  end
end
