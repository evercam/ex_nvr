defmodule ExNVR.DevicesTest do
  use ExNVR.DataCase

  alias ExNVR.Devices
  alias ExNVR.Model.Device

  import ExNVR.DevicesFixtures

  @valid_camera_name "camera 1"
  @valid_vendor "Hikvision"
  @valid_mac "00:1b:63:84:45:e6"
  @valid_url "url.com"
  @valid_model "DS-2CD2386G2-ISU/SL"

  @moduletag :tmp_dir

  setup ctx do
    %{settings: %{storage_address: ctx.tmp_dir}}
  end

  describe "list_devices/1" do
    test "returns empty list if no device exists" do
      assert Enum.empty?(Devices.list())
    end

    test "returns all the devices", ctx do
      devices = [
        device_fixture(%{settings: ctx.settings}),
        device_fixture(%{settings: ctx.settings})
      ]

      assert devices == Devices.list()
    end

    test "filter devices by state", ctx do
      device_1 = device_fixture(%{state: :recording, settings: ctx.settings})
      device_2 = device_fixture(%{state: :failed, settings: ctx.settings})
      device_3 = device_fixture(%{state: :stopped, settings: ctx.settings})

      assert [device_1] == Devices.list(%{state: :recording})
      assert [device_2, device_3] == Devices.list(%{state: [:failed, :stopped]})
    end
  end

  describe "create/1" do
    test "requires name and type" do
      {:error, changeset} = Devices.create(%{})

      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "validate type is in the specified enum" do
      {:error, changeset} = Devices.create(%{name: @valid_camera_name, type: "RANDOM"})

      assert %{type: ["is invalid"]} = errors_on(changeset)
    end

    test "requires stream config when type is file" do
      {:error, changeset} =
        Devices.create(%{
          name: @valid_camera_name,
          type: "file",
          settings: valid_device_settings()
        })

      assert %{
               stream_config: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "requires File location when type is File" do
      {:error, changeset} =
        Devices.create(%{
          name: @valid_camera_name,
          type: "file",
          stream_config: %{},
          settings: valid_device_settings()
        })

      assert %{
               stream_config: %{duration: ["can't be blank"], filename: ["can't be blank"]}
             } = errors_on(changeset)
    end

    test "requires stream config when type is ip" do
      {:error, changeset} =
        Devices.create(%{name: @valid_camera_name, type: "ip", settings: valid_device_settings()})

      assert %{
               stream_config: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "requires stream_uri" do
      {:error, changeset} =
        Devices.create(%{
          name: @valid_camera_name,
          type: "ip",
          stream_config: %{},
          settings: valid_device_settings()
        })

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

    test "require settings" do
      {:error, changeset} = Devices.create(%{})
      assert %{settings: ["can't be blank"]} = errors_on(changeset)

      {:error, changeset} = Devices.create(%{settings: %{}})
      assert %{settings: %{storage_address: ["can't be blank"]}} = errors_on(changeset)
    end

    test "override_on_full_disk_threshold is between 0 and 100", %{tmp_dir: tmp_dir} do
      {:error, changeset} =
        Devices.create(
          valid_device_attributes(%{
            name: @valid_camera_name,
            settings: %{
              storage_address: tmp_dir,
              override_on_full_disk_threshold: 120
            }
          })
        )

      assert %{settings: %{override_on_full_disk_threshold: ["value must be between 0 and 100"]}} =
               errors_on(changeset)

      {:error, changeset} =
        Devices.create(
          valid_device_attributes(%{
            name: @valid_camera_name,
            settings: %{
              storage_address: tmp_dir,
              override_on_full_disk_threshold: -40
            }
          })
        )

      assert %{settings: %{override_on_full_disk_threshold: ["value must be between 0 and 100"]}} =
               errors_on(changeset)
    end

    test "create a new device", %{tmp_dir: tmp_dir} do
      {:ok, device} =
        Devices.create(
          valid_device_attributes(%{
            name: @valid_camera_name,
            vendor: @valid_vendor,
            mac: @valid_mac,
            url: @valid_url,
            model: @valid_model,
            settings: %{
              storage_address: tmp_dir,
              override_on_full_disk: true
            }
          })
        )

      assert device.id
      assert device.name == @valid_camera_name
      assert device.vendor == @valid_vendor
      assert device.mac == @valid_mac
      assert device.url == @valid_url
      assert device.model == @valid_model
      assert device.settings.storage_address == tmp_dir
      assert device.settings.override_on_full_disk

      # assert folder created
      assert File.exists?(Device.base_dir(device))
      assert File.exists?(Device.recording_dir(device))
      assert File.exists?(Device.recording_dir(device, :low))
      assert File.exists?(Device.bif_dir(device))
    end
  end

  describe "update/2" do
    setup ctx do
      %{device: device_fixture(%{settings: ctx.settings})}
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
          stream_config: %{sub_stream_uri: stream_uri},
          vendor: @valid_vendor,
          mac: @valid_mac,
          url: @valid_url,
          model: @valid_model,
          settings: %{
            generate_bif: true,
            override_on_full_disk: true
          }
        })

      assert device.name == @valid_camera_name
      assert device.vendor == @valid_vendor
      assert device.mac == @valid_mac
      assert device.url == @valid_url
      assert device.model == @valid_model
      assert device.stream_config.sub_stream_uri == stream_uri
      assert device.settings.generate_bif
      assert device.settings.override_on_full_disk
    end
  end

  describe "update_state/2" do
    setup ctx do
      %{device: device_fixture(%{settings: ctx.settings})}
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
      assert changeset.required == [:stream_config, :name, :type, :settings]
    end

    test "requires Stream config (camera config) to be set when type is IP" do
      name = "Camera 1"

      assert %Ecto.Changeset{} =
               changeset =
               Devices.change_device_creation(
                 %Device{},
                 valid_device_attributes(%{name: name, type: "ip"})
               )

      assert changeset.required == [:stream_config, :name, :type, :settings]
    end

    test "allows fields to be set (Type: ip)" do
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
                   type: "ip",
                   stream_config: stream_config
                 })
               )

      assert changeset.valid?
      assert get_change(changeset, :name) == name

      assert %Ecto.Changeset{} = config_changeset = get_change(changeset, :stream_config)
      assert get_change(config_changeset, :stream_uri) == stream_config.stream_uri
    end

    test "requires Stream config to be set when type is file" do
      name = "Camera 1"

      assert %Ecto.Changeset{} =
               changeset =
               Devices.change_device_creation(
                 %Device{},
                 valid_device_attributes(%{name: name, type: "file"})
               )

      assert changeset.required == [:stream_config, :name, :type, :settings]
    end

    test "allows fields to be set (Type: file)" do
      name = "Camera 1"

      stream_config = %{
        filename: "big_buck.mp4",
        duration: 1000
      }

      assert %Ecto.Changeset{} =
               changeset =
               Devices.change_device_creation(
                 %Device{},
                 valid_device_attributes(%{
                   name: name,
                   type: "file",
                   stream_config: stream_config
                 })
               )

      assert changeset.valid?
      assert get_change(changeset, :name) == name
      assert get_change(changeset, :type) == :file

      assert %Ecto.Changeset{} = config_changeset = get_change(changeset, :stream_config)
      assert get_change(config_changeset, :filename) == stream_config.filename
      assert get_change(config_changeset, :duration) == stream_config.duration
    end
  end

  test "get recordings dir", ctx do
    device = device_fixture(%{settings: ctx.settings})

    assert Path.join([ctx.tmp_dir, "ex_nvr", device.id]) == Device.base_dir(device)

    assert Path.join([ctx.tmp_dir, "ex_nvr", device.id, "hi_quality"]) ==
             Device.recording_dir(device)

    assert Path.join([ctx.tmp_dir, "ex_nvr", device.id, "lo_quality"]) ==
             Device.recording_dir(device, :low)

    assert Path.join([ctx.tmp_dir, "ex_nvr", device.id, "bif"]) == Device.bif_dir(device)
  end
end
