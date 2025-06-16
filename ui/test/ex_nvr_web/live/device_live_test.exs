defmodule ExNVRWeb.DeviceLiveTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures}
  import Phoenix.LiveViewTest

  alias ExNVR.Devices
  alias ExNVR.Model.Device

  @moduletag :tmp_dir

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  describe "Device page" do
    test "render new device page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/devices/new")

      assert html =~ "Create a new device"
      assert html =~ "Creating..."
    end

    test "render update device page", %{conn: conn, tmp_dir: tmp_dir} do
      device = camera_device_fixture(tmp_dir)
      {:ok, _lv, html} = live(conn, ~p"/devices/#{device.id}")

      assert html =~ "Update a device"
      assert html =~ "Updating..."
    end
  end

  describe "Create device" do
    test "create a new FILE device", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/devices/new")

      file_content = File.read!("test/fixtures/big_buck.mp4")

      render_change(lv, :validate, %{"device" => %{"type" => "file"}})

      lv
      |> file_input("#device_form", :file_to_upload, [
        %{
          name: "big_buck.mp4",
          content: file_content,
          size: byte_size(file_content),
          type: "video/mp4"
        }
      ])
      |> render_upload("big_buck.mp4")

      {:ok, conn} =
        lv
        |> form("#device_form", %{
          "device" => %{
            "name" => "My Device",
            "type" => "file",
            "storage_config" => %{"address" => "/tmp"}
          }
        })
        |> render_submit()
        |> follow_redirect(conn, ~p"/devices")

      assert [created_device] = Devices.list()

      assert created_device.name == "My Device"
      assert created_device.type == :file
      assert created_device.storage_config.address == "/tmp"
      assert created_device.stream_config.filename == "big_buck.mp4"

      assert File.exists?(Device.file_location(created_device))
      File.rm(Device.file_location(created_device))

      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Device created successfully"
    end

    test "renders errors on file upload with wrong type", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/devices/new")

      file_content = File.read!("test/fixtures/device_file_with_wrong_type.txt")

      render_change(lv, :validate, %{"device" => %{"type" => "file"}})

      {:error, [[_, error]]} =
        lv
        |> file_input("#device_form", :file_to_upload, [
          %{
            name: "device_file_with_wrong_type.txt",
            content: file_content,
            size: byte_size(file_content),
            type: "text/txt"
          }
        ])
        |> render_upload("device_file_with_wrong_type.txt")

      assert error == :not_accepted
    end

    test "create a new IP device", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/devices/new")

      {:ok, conn} =
        lv
        |> form("#device_form", %{
          "device" => %{
            "name" => "My Device",
            "type" => "ip",
            "vendor" => "HIKVISION",
            "credentials" => %{
              "username" => "user",
              "password" => "pass"
            },
            "stream_config" => %{
              "stream_uri" => "rtsp://localhost:554"
            },
            "storage_config" => %{
              "address" => "/tmp"
            }
          }
        })
        |> render_submit()
        |> follow_redirect(conn, ~p"/devices")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Device created successfully"
    end

     test "create a new IP device with custom schedules", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/devices/new")

      custom_storage = %{"1" => ["08:00-12:00"]}
      custom_snapshot = %{"2" => ["09:00-10:00"]}

      lv = render_change(lv, "update_storage_schedule", custom_storage)
      lv = render_change(lv, "update_snapshot_schedule", custom_snapshot)

      {:ok, conn} =
        lv
        |> form("#device_form", %{
          "device" => %{
            "name" => "Scheduled IP Device",
            "type" => "ip",
            "vendor" => "HIKVISION",
            "credentials" => %{ "username" => "user", "password" => "pass" },
            "stream_config" => %{ "stream_uri" => "rtsp://localhost:554" },
            "storage_config" => %{ "address" => "/tmp" }
          }
        })
        |> render_submit()
        |> follow_redirect(conn, ~p"/devices")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Device created successfully"

      [created] = Devices.list()
      assert created.storage_config.schedule == custom_storage
      assert created.snapshot_config.schedule == custom_snapshot
    end

    test "renders errors on form submission", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/devices/new")

      result =
        lv
        |> form("#device_form", %{
          "device" => %{
            "name" => "My Device",
            "type" => "ip",
            "stream_config" => %{"stream_uri" => "rtsp://"},
            "storage_config" => %{
              "address" => "/tmp"
            }
          }
        })
        |> render_submit()

      assert result =~ "invalid rtsp uri"
      assert Enum.empty?(Devices.list())
    end
  end

  describe "Update a device" do
    setup ctx do
      %{
        device: camera_device_fixture(ctx.tmp_dir),
        file_device: file_device_fixture()
      }
    end

    test "update an IP Camera device", %{conn: conn, device: device} do
      {:ok, lv, _} = live(conn, ~p"/devices/#{device.id}")

      new_storage_schedule = %{"3" => ["06:00-18:00"]}
      lv = render_event(lv, :change, "update_storage_schedule", new_storage_schedule)

      new_snapshot_schedule = %{"1" => ["06:00-18:00", "19:00-21:30"]}
      lv = render_event(lv, :change, "update_snapshot_schedule", new_snapshot_schedule)

      {:ok, conn} =
        lv
        |> form("#device_form", %{
          "device" => %{
            "name" => "My Updated Device",
            "stream_config" => %{
              "stream_uri" => "rtsp://localhost:554"
            }
          }
        })
        |> render_submit()
        |> follow_redirect(conn, ~p"/devices")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Device updated successfully"

      assert updated_device = Devices.get(device.id)
      assert updated_device.name == "My Updated Device"
      assert updated_device.stream_config.stream_uri == "rtsp://localhost:554"
      assert updated_device.storage_config.schedule == new_storage_schedule
      assert updated_device.snapshot_config.schedule == new_snapshot_schedule
    end

    test "renders errors on invalid update params for an IP Device", %{conn: conn, device: device} do
      {:ok, lv, _} = live(conn, ~p"/devices/#{device.id}")

      result =
        lv
        |> form("#device_form", %{
          "device" => %{
            "stream_config" => %{"stream_uri" => "rtsp://"}
          }
        })
        |> render_submit()

      assert result =~ "invalid rtsp uri"
    end

    test "update a File Source device", %{conn: conn, file_device: device} do
      {:ok, lv, _} = live(conn, ~p"/devices/#{device.id}")

      {:ok, conn} =
        lv
        |> form("#device_form", %{
          "device" => %{
            "name" => "My Updated Device",
            "timezone" => "Pacific/Apia"
          }
        })
        |> render_submit()
        |> follow_redirect(conn, ~p"/devices")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Device updated successfully"

      assert updated_device = Devices.get(device.id)
      assert updated_device.name == "My Updated Device"
      assert updated_device.timezone == "Pacific/Apia"
    end
  end
end
