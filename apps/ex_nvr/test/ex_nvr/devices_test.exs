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
      devices = [device_fixture(), device_fixture()]
      assert devices == Devices.list()
    end

    test "filter devices by state" do
      device_1 = device_fixture(%{state: :recording})
      device_2 = device_fixture(%{state: :failed})
      device_3 = device_fixture(%{state: :stopped})

      assert [device_1] == Devices.list(%{state: :recording})
      assert [device_2, device_3] == Devices.list(%{state: [:failed, :stopped]})
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

    test "requires stream config when type is FILE" do
      {:error, changeset} = Devices.create(%{name: @valid_camera_name, type: "FILE"})

      assert %{
               stream_config: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "requires File location when type is File" do
      {:error, changeset} =
        Devices.create(%{name: @valid_camera_name, type: "FILE", stream_config: %{}})

      assert %{
               stream_config: %{location: ["can't be blank"]}
             } = errors_on(changeset)
    end

    test "validate File extension when type is FILE" do
      {:error, changeset} =
        Devices.create(
          valid_device_attributes(%{stream_config: %{location: "localhost"}}, type: "FILE")
        )

      assert %{
               stream_config: %{location: ["invalid File location"]}
             } = errors_on(changeset)

      {:error, changeset} =
        Devices.create(
          valid_device_attributes(%{stream_config: %{location: "/Users/"}}, type: "FILE")
        )

      assert %{
               stream_config: %{location: ["invalid File location"]}
             } = errors_on(changeset)
    end

    test "requires stream config when type is IP" do
      {:error, changeset} = Devices.create(%{name: @valid_camera_name, type: "IP"})

      assert %{
               stream_config: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "requires stream_uri" do
      {:error, changeset} =
        Devices.create(%{name: @valid_camera_name, type: "IP", stream_config: %{}})

      assert %{
               stream_config: %{stream_uri: ["can't be blank"]}
             } = errors_on(changeset)
    end

    test "validate (sub)stream uri" do
      {:error, changeset} =
        Devices.create(valid_device_attributes(%{stream_config: %{stream_uri: "localhost"}}))

      assert %{
               stream_config: %{stream_uri: ["scheme should be rtsp"]}
             } = errors_on(changeset)

      {:error, changeset} =
        Devices.create(valid_device_attributes(%{stream_config: %{stream_uri: "rtsp://"}}))

      assert %{
               stream_config: %{stream_uri: ["invalid rtsp uri"]}
             } = errors_on(changeset)
    end

    test "create a new device" do
      {:ok, device} = Devices.create(valid_device_attributes(%{name: @valid_camera_name}))
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
          stream_config: %{sub_stream_uri: stream_uri}
        })

      assert device.name == @valid_camera_name
      assert device.stream_config.sub_stream_uri == stream_uri
    end
  end

  describe "update_state/2" do
    setup do
      %{device: device_fixture()}
    end

    test "device state updated", %{device: device} do
      {:ok, device} = Devices.update_state(device, :failed)
      assert device.state == :failed
    end

    test "cannot update device state", %{device: device} do
      assert {:error, _changeset} = Devices.update_state(device, :unknown)
    end
  end

  describe "change_user_creation/1" do
    test "returns changeset" do
      assert %Ecto.Changeset{} = changeset = Devices.change_device_creation(%Device{})
      assert changeset.required == [:name, :type]
    end

    test "requires Stream config (camera config) to be set when type is IP" do
      name = "Camera 1"

      assert %Ecto.Changeset{} =
               changeset =
               Devices.change_device_creation(
                 %Device{},
                 valid_device_attributes(%{name: name, type: "ip"})
               )

      assert changeset.required == [:stream_config, :name, :type]
    end

    test "allows fields to be set (Type: IP)" do
      name = "Camera 1"

      stream_config = %{
        stream_uri: valid_rtsp_url()
      }

      assert %Ecto.Changeset{} =
               changeset =
               Devices.change_device_creation(
                 %Device{},
                 valid_device_attributes(%{
                   name: name,
                   type: "IP",
                   stream_config: stream_config
                 })
               )

      assert changeset.valid?
      assert get_change(changeset, :name) == name
      assert get_change(changeset, :type) == :ip

      assert %Ecto.Changeset{} = config_changeset = get_change(changeset, :stream_config)
      assert get_change(config_changeset, :stream_uri) == stream_config.stream_uri
    end

    test "requires Stream config to be set when type is FILE" do
      name = "Camera 1"

      assert %Ecto.Changeset{} =
               changeset =
               Devices.change_device_creation(
                 %Device{},
                 valid_device_attributes(%{name: name, type: "FILE"})
               )

      assert changeset.required == [:stream_config, :name, :type]
    end

    test "allows fields to be set (Type: FILE)" do
      name = "Camera 1"

      stream_config = %{
        location: valid_file_location()
      }

      assert %Ecto.Changeset{} =
               changeset =
               Devices.change_device_creation(
                 %Device{},
                 valid_device_attributes(%{
                   name: name,
                   type: "FILE",
                   stream_config: stream_config
                 })
               )

      assert changeset.valid?
      assert get_change(changeset, :name) == name
      assert get_change(changeset, :type) == :FILE

      assert %Ecto.Changeset{} = config_changeset = get_change(changeset, :stream_config)
      assert get_change(config_changeset, :location) == stream_config.location
    end
  end
end
