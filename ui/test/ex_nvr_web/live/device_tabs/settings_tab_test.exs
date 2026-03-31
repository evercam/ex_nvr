defmodule ExNVRWeb.DeviceTabs.SettingsTabTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures}
  import Phoenix.LiveViewTest

  alias ExNVR.Devices

  @moduletag :tmp_dir

  defp open_settings_tab(conn, device) do
    {:ok, lv, _html} = live(conn, ~p"/devices/#{device.id}/details")
    lv |> element("[phx-click='switch_tab'][phx-value-tab='settings']") |> render_click()
    lv
  end

  defp form_id(device, section), do: "##{section}_form_#{device.id}"

  describe "Settings tab - rendering" do
    setup %{conn: conn, tmp_dir: tmp_dir} do
      %{
        conn: log_in_user(conn, user_fixture()),
        device: camera_device_fixture(tmp_dir)
      }
    end

    test "renders all section forms for an IP device", %{conn: conn, device: device} do
      lv = open_settings_tab(conn, device)

      assert has_element?(lv, form_id(device, "general"))
      assert has_element?(lv, form_id(device, "connection"))
      assert has_element?(lv, form_id(device, "stream_config"))
      assert has_element?(lv, form_id(device, "storage"))
      assert has_element?(lv, form_id(device, "snapshot"))
      assert has_element?(lv, form_id(device, "advanced"))
    end

    test "each section card has its own Save button", %{conn: conn, device: device} do
      lv = open_settings_tab(conn, device)

      assert lv |> element(form_id(device, "general"), "Save") |> has_element?()
      assert lv |> element(form_id(device, "connection"), "Save") |> has_element?()
      assert lv |> element(form_id(device, "stream_config"), "Save") |> has_element?()
      assert lv |> element(form_id(device, "storage"), "Save") |> has_element?()
      assert lv |> element(form_id(device, "snapshot"), "Save") |> has_element?()
      assert lv |> element(form_id(device, "advanced"), "Save") |> has_element?()
    end

    test "renders name and timezone fields in General section", %{conn: conn, device: device} do
      lv = open_settings_tab(conn, device)

      assert has_element?(lv, "h3", "General")
      assert has_element?(lv, "input[name='device[name]']")
      assert has_element?(lv, "select[name='device[timezone]']")
    end

    test "renders Connection section with url, vendor and credentials for IP cameras", %{
      conn: conn,
      device: device
    } do
      lv = open_settings_tab(conn, device)

      assert has_element?(lv, "h3", "Connection")
      assert has_element?(lv, "input[name='device[url]']")
      assert has_element?(lv, "select[name='device[vendor]']")
      assert has_element?(lv, "input[name='device[credentials][username]']")
      assert has_element?(lv, "input[type='password'][name='device[credentials][password]']")
      assert has_element?(lv, "button[aria-label='Toggle password visibility']")
    end

    test "renders Stream Configuration section for IP cameras", %{conn: conn, device: device} do
      lv = open_settings_tab(conn, device)

      assert has_element?(lv, "h3", "Stream Configuration")
      assert has_element?(lv, "input[name='device[stream_config][stream_uri]']")
      assert has_element?(lv, "input[name='device[stream_config][snapshot_uri]']")
      assert has_element?(lv, "input[name='device[stream_config][sub_stream_uri]']")
      assert has_element?(lv, "input[name='device[stream_config][sub_snapshot_uri]']")
    end

    test "renders Storage section for all devices with recording mode selector", %{
      conn: conn,
      device: device
    } do
      lv = open_settings_tab(conn, device)

      assert has_element?(lv, "h3", "Storage")
      assert has_element?(lv, "select[name='device[storage_config][recording_mode]']")
    end

    test "renders storage sub-fields when recording mode is not never", %{
      conn: conn,
      device: device
    } do
      lv = open_settings_tab(conn, device)

      assert has_element?(lv, "input[name='device[storage_config][full_drive_threshold]']")
      assert has_element?(lv, "select[name='device[storage_config][full_drive_action]']")
      assert has_element?(lv, "select[name='device[storage_config][record_sub_stream]']")
    end

    test "renders Advanced section for IP cameras when recording", %{conn: conn, device: device} do
      lv = open_settings_tab(conn, device)

      assert has_element?(lv, "h3", "Advanced")
      assert has_element?(lv, "input[name='device[settings][generate_bif]']")
      assert has_element?(lv, "input[name='device[settings][enable_lpr]']")
    end

    test "does not render IP-only sections for file devices", %{conn: conn} do
      device = file_device_fixture()
      lv = open_settings_tab(conn, device)

      refute has_element?(lv, "h3", "Connection")
      refute has_element?(lv, "h3", "Stream Configuration")
      refute has_element?(lv, "h3", "Webcam Settings")
      refute has_element?(lv, "h3", "Snapshot Upload")
      refute has_element?(lv, "h3", "Advanced")
    end
  end

  describe "Settings tab - recording mode visibility" do
    setup %{conn: conn, tmp_dir: tmp_dir} do
      %{
        conn: log_in_user(conn, user_fixture()),
        device: camera_device_fixture(tmp_dir)
      }
    end

    test "hides storage sub-fields when recording mode changed to never", %{
      conn: conn,
      device: device
    } do
      lv = open_settings_tab(conn, device)

      html =
        lv
        |> form(form_id(device, "storage"), %{
          "device" => %{"storage_config" => %{"recording_mode" => "never"}}
        })
        |> render_change()

      refute html =~ "Full Drive Threshold"
      refute html =~ "Full Drive Action"
    end

    test "shows storage sub-fields when recording mode is always", %{conn: conn, device: device} do
      lv = open_settings_tab(conn, device)

      html =
        lv
        |> form(form_id(device, "storage"), %{
          "device" => %{"storage_config" => %{"recording_mode" => "always"}}
        })
        |> render_change()

      assert html =~ "Full Drive Threshold"
      assert html =~ "Full Drive Action"
    end

    test "hides Advanced section when recording mode is never", %{conn: conn, device: device} do
      lv = open_settings_tab(conn, device)

      lv
      |> form(form_id(device, "storage"), %{
        "device" => %{"storage_config" => %{"recording_mode" => "never"}}
      })
      |> render_change()

      refute has_element?(lv, "h3", "Advanced")
    end
  end

  describe "Settings tab - saving per section" do
    setup %{conn: conn, tmp_dir: tmp_dir} do
      %{
        conn: log_in_user(conn, user_fixture()),
        device: camera_device_fixture(tmp_dir)
      }
    end

    test "saves General section and shows Saved indicator", %{conn: conn, device: device} do
      lv = open_settings_tab(conn, device)

      html =
        lv
        |> form(form_id(device, "general"), %{
          "device" => %{"name" => "Updated Name"}
        })
        |> render_submit()

      assert html =~ "Saved"
      assert Devices.get(device.id).name == "Updated Name"
    end

    test "saves Connection section and shows Saved indicator", %{conn: conn, device: device} do
      lv = open_settings_tab(conn, device)

      html =
        lv
        |> form(form_id(device, "connection"), %{
          "device" => %{
            "credentials" => %{"username" => "newuser", "password" => "newpass"}
          }
        })
        |> render_submit()

      assert html =~ "Saved"
      assert Devices.get(device.id).credentials.username == "newuser"
    end

    test "saves Stream Config section and shows Saved indicator", %{conn: conn, device: device} do
      lv = open_settings_tab(conn, device)

      html =
        lv
        |> form(form_id(device, "stream_config"), %{
          "device" => %{
            "stream_config" => %{"stream_uri" => "rtsp://newcamera:554/stream"}
          }
        })
        |> render_submit()

      assert html =~ "Saved"
      assert Devices.get(device.id).stream_config.stream_uri == "rtsp://newcamera:554/stream"
    end

    test "saves Storage section and shows Saved indicator", %{conn: conn, device: device} do
      lv = open_settings_tab(conn, device)

      html =
        lv
        |> form(form_id(device, "storage"), %{
          "device" => %{
            "storage_config" => %{
              "recording_mode" => "always",
              "full_drive_threshold" => "80",
              "full_drive_action" => "nothing",
              "record_sub_stream" => "never"
            }
          }
        })
        |> render_submit()

      assert html =~ "Saved"
      assert Devices.get(device.id).storage_config.full_drive_threshold == 80.0
    end

    test "saves Advanced section and shows Saved indicator", %{conn: conn, device: device} do
      lv = open_settings_tab(conn, device)

      html =
        lv
        |> form(form_id(device, "advanced"), %{
          "device" => %{
            "settings" => %{"generate_bif" => "false", "enable_lpr" => "false"}
          }
        })
        |> render_submit()

      assert html =~ "Saved"
      assert Devices.get(device.id).settings.generate_bif == false
    end

    test "Saved indicator only appears in the section that was saved", %{
      conn: conn,
      device: device
    } do
      lv = open_settings_tab(conn, device)

      lv
      |> form(form_id(device, "general"), %{
        "device" => %{"name" => "New Name"}
      })
      |> render_submit()

      # Saved shown in general form
      assert lv |> element(form_id(device, "general"), "Saved") |> has_element?()
      # Not shown in other sections
      refute lv |> element(form_id(device, "storage"), "Saved") |> has_element?()
    end

    test "shows validation error for invalid stream URI in Stream Config section", %{
      conn: conn,
      device: device
    } do
      lv = open_settings_tab(conn, device)

      html =
        lv
        |> form(form_id(device, "stream_config"), %{
          "device" => %{
            "stream_config" => %{"stream_uri" => "not-valid"}
          }
        })
        |> render_submit()

      refute html =~ "Saved"
      assert html =~ "scheme should be rtsp"
    end

    test "shows validation error for blank name in General section", %{
      conn: conn,
      device: device
    } do
      lv = open_settings_tab(conn, device)

      html =
        lv
        |> form(form_id(device, "general"), %{
          "device" => %{"name" => ""}
        })
        |> render_submit()

      refute html =~ "Saved"
      assert html =~ "can&#39;t be blank"
    end
  end

  describe "Settings tab - delete device" do
    setup %{conn: conn, tmp_dir: tmp_dir} do
      %{
        conn: log_in_user(conn, user_fixture()),
        device: camera_device_fixture(tmp_dir)
      }
    end

    test "shows Danger Zone section for admin users", %{conn: conn, device: device} do
      lv = open_settings_tab(conn, device)

      assert has_element?(lv, "#danger_zone_#{device.id}")
      assert has_element?(lv, "button", "Delete Device")
    end

    test "shows confirmation buttons after clicking Delete Device", %{
      conn: conn,
      device: device
    } do
      lv = open_settings_tab(conn, device)

      lv |> element("button", "Delete Device") |> render_click()

      assert has_element?(lv, "button", "Yes, delete")
      assert has_element?(lv, "button", "Cancel")
      refute has_element?(lv, "button", "Delete Device")
    end

    test "Cancel hides confirmation and restores Delete Device button", %{
      conn: conn,
      device: device
    } do
      lv = open_settings_tab(conn, device)

      lv |> element("button", "Delete Device") |> render_click()
      lv |> element("button", "Cancel") |> render_click()

      assert has_element?(lv, "button", "Delete Device")
      refute has_element?(lv, "button", "Yes, delete")
    end

    test "confirming delete removes the device and redirects to /devices", %{
      conn: conn,
      device: device
    } do
      lv = open_settings_tab(conn, device)

      lv |> element("button", "Delete Device") |> render_click()

      assert {:error, {:live_redirect, %{to: "/devices"}}} =
               lv |> element("button", "Yes, delete") |> render_click()

      assert Devices.get(device.id) == nil
    end
  end
end
