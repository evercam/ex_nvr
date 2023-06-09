defmodule ExNVR.DevicesTest do
  use ExNVR.DataCase

  alias ExNVR.Devices
  alias ExNVR.Model.Device

  import ExNVR.DevicesFixtures

  @valid_camera_name "camera 1"

  describe "list_devices/1" do
    test "returns empty list if no device exists" do
      assert Enum.empty?(Devices.list())
    end

    test "returns all the devices" do
      [%{id: device_one_id}, %{id: device_two_id}] = [device_fixture(), device_fixture()]
      assert Enum.sort([device_one_id, device_two_id]) == Devices.list() |> Enum.map(& &1.id)
    end
  end

  describe "create/1" do
    test "requires name and type" do
      {:error, changeset} = Devices.create(%{})

      assert %{
               name: ["can't be blank"],
               type: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validate type is in the specified enum" do
      {:error, changeset} = Devices.create(%{name: @valid_camera_name, type: "RANDOM"})

      assert %{type: ["is invalid"]} = errors_on(changeset)
    end

    test "requires ip camera config when type is IP" do
      {:error, changeset} = Devices.create(%{name: @valid_camera_name, type: "IP"})

      assert %{
               ip_camera_config: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "requires stream_uri" do
      {:error, changeset} =
        Devices.create(%{name: @valid_camera_name, type: "IP", ip_camera_config: %{}})

      assert %{
               ip_camera_config: %{stream_uri: ["can't be blank"]}
             } = errors_on(changeset)
    end

    test "validate (sub)stream uri" do
      {:error, changeset} =
        Devices.create(valid_device_attributes(%{ip_camera_config: %{stream_uri: "localhost"}}))

      assert %{
               ip_camera_config: %{stream_uri: ["scheme should be rtsp"]}
             } = errors_on(changeset)

      {:error, changeset} =
        Devices.create(valid_device_attributes(%{ip_camera_config: %{stream_uri: "rtsp://"}}))

      assert %{
               ip_camera_config: %{stream_uri: ["invalid rtsp uri"]}
             } = errors_on(changeset)
    end

    test "create a new device" do
      {:ok, device} = Devices.create(valid_device_attributes(name: @valid_camera_name))
      assert device.id
      assert device.name == @valid_camera_name
    end
  end

  describe "update/2" do
    setup do
      %{device: device_fixture()}
    end

    test "type cannot be updated", %{device: device} do
      device_type = device.type
      {:ok, device} = Devices.update(device, %{type: "Web"})

      assert device.type == device_type
    end

    test "update device", %{device: device} do
      stream_uri = "rtsp://localhost:554/video1"

      {:ok, device} =
        Devices.update(device, %{
          name: @valid_camera_name,
          ip_camera_config: %{sub_stream_uri: stream_uri}
        })

      assert device.name == @valid_camera_name
      assert device.ip_camera_config.sub_stream_uri == stream_uri
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
