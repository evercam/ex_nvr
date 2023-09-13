defmodule ExNVRWeb.DeviceLiveTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures}
  import Phoenix.LiveViewTest

  alias ExNVR.Devices

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  describe "Device page" do
    test "render new device page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/devices/new")

      assert html =~ "Create a new device"
      assert html =~ "Creating..."
    end

    test "render update device page", %{conn: conn} do
      device = device_fixture()
      {:ok, _lv, html} = live(conn, ~p"/devices/#{device.id}")

      assert html =~ "Update a device"
      assert html =~ "Updating..."
    end
  end

  describe "Create device" do
    test "create a new FILE device", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/devices/new")

      {:ok, conn} =
        lv
        |> form("#device_form", %{
          "device" => %{
            "name" => "My Device",
            "type" => "file",
            "stream_config" => %{
              "location" => valid_file_location()
            }
          }
        })
        |> render_submit()
        |> follow_redirect(conn, ~p"/devices")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Device created successfully"
    end

    test "renders errors on form submission TYPE: FILE", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/devices/new")

      result =
        lv
        |> form("#device_form", %{
          "device" => %{
            "name" => "My Device",
            "type" => "file",
            "stream_config" => %{"location" => "rtsp://"}
          }
        })
        |> render_submit()

      assert result =~ "invalid File location"
      assert Enum.empty?(Devices.list())
    end

    test "create a new IP device", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/devices/new")

      {:ok, conn} =
        lv
        |> form("#device_form", %{
          "device" => %{
            "name" => "My Device",
            "type" => "ip",
            "credentials" => %{
              "username" => "user",
              "password" => "pass"
            },
            "stream_config" => %{
              "stream_uri" => "rtsp://localhost:554"
            }
          }
        })
        |> render_submit()
        |> follow_redirect(conn, ~p"/devices")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Device created successfully"
    end

    test "renders errors on form submission", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/devices/new")

      result =
        lv
        |> form("#device_form", %{
          "device" => %{
            "name" => "My Device",
            "type" => "ip",
            "stream_config" => %{"stream_uri" => "rtsp://"}
          }
        })
        |> render_submit()

      assert result =~ "invalid rtsp uri"
      assert Enum.empty?(Devices.list())
    end
  end

  describe "Update a device" do
    setup do
      %{device: device_fixture(), file_device: device_fixture(%{}, device_type: "file")}
    end

    test "update an IP Camera device", %{conn: conn, device: device} do
      {:ok, lv, _} = live(conn, ~p"/devices/#{device.id}")

      view =
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

      assert view =~ "My Updated Device"
      assert view =~ "rtsp://localhost:554"

      assert updated_device = Devices.get(device.id)
      assert updated_device.name == "My Updated Device"
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

      view =
        lv
        |> form("#device_form", %{
          "device" => %{
            "name" => "My Updated Device",
            "stream_config" => %{
              "location" => "/Users/Recordings/my_stream.mp4"
            }
          }
        })
        |> render_submit()

      assert view =~ "My Updated Device"
      assert view =~ "/Users/Recordings/my_stream.mp4"

      assert updated_device = Devices.get(device.id)
      assert updated_device.name == "My Updated Device"
    end

    test "renders errors on invalid update params for a FILE type Device", %{
      conn: conn,
      file_device: device
    } do
      {:ok, lv, _} = live(conn, ~p"/devices/#{device.id}")

      result =
        lv
        |> form("#device_form", %{
          "device" => %{
            "stream_config" => %{"location" => "/Users/Recordings/nothing.pdf"}
          }
        })
        |> render_submit()

      assert result =~ "invalid File location"
    end
  end
end
