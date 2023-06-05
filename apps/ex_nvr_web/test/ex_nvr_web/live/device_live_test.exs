defmodule ExNVRWeb.DeviceLiveTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures}
  import Phoenix.LiveViewTest

  alias ExNVR.Devices

  describe "Devices page" do
    setup do
      %{device: device_fixture()}
    end

    test "render devices page", %{conn: conn, device: device} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices")

      assert html =~ "Add device"
      assert html =~ device.name
      assert html =~ device.id
    end

    test "redirect if user is not logged in", %{conn: conn} do
      {:error, redirect} = live(conn, ~p"/devices")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/login"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end

  describe "Create device" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, user_fixture())}
    end

    test "create a new device", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/devices")

      result =
        lv
        |> form("#device_form", %{
          "device" => %{
            "name" => "My Device",
            "type" => "IP",
            "ip_camera_config" => %{
              "stream_uri" => "rtsp://localhost:554",
              "username" => "user",
              "password" => "pass"
            }
          }
        })
        |> render_submit()

      assert result =~ "My Device"
      assert length(Devices.list()) == 1
    end

    test "renders errors on form submission", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/devices")

      result =
        lv
        |> form("#device_form", %{
          "device" => %{
            "name" => "My Device",
            "type" => "IP",
            "ip_camera_config" => %{"stream_uri" => "rtsp://"}
          }
        })
        |> render_submit()

      assert result =~ "invalid rtsp uri"
      assert Enum.empty?(Devices.list())
    end
  end
end
