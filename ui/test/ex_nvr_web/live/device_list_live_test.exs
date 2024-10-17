defmodule ExNVRWeb.DeviceListLiveTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures}
  import Phoenix.LiveViewTest

  @moduletag :tmp_dir

  describe "Device list page" do
    setup ctx do
      %{device: camera_device_fixture(ctx.tmp_dir)}
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

    test "redirect when clicking on add device", %{conn: conn} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices")

      {:error, redirect} =
        lv
        |> element(~s|a[href="/devices/new"]|)
        |> render_click()

      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/devices/new"
    end
  end

  describe "Start/Stop device recording" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, user_fixture())}
    end

    test "Stop recording", %{conn: conn, tmp_dir: tmp_dir} do
      device = camera_device_fixture(tmp_dir, %{state: :recording})

      {:ok, lv, html} = live(conn, ~p"/devices")

      assert html =~ "Stop recording"

      html =
        lv
        |> element(~s|a|, "Stop recording")
        |> render_click()

      assert html =~ "Start recording"
      assert ExNVR.Devices.get!(device.id).state == :stopped
    end

    test "Start recording", %{conn: conn, tmp_dir: tmp_dir} do
      device = camera_device_fixture(tmp_dir, %{state: :stopped})

      {:ok, lv, html} = live(conn, ~p"/devices")

      assert html =~ "Start recording"

      html =
        lv
        |> element(~s|a|, "Start recording")
        |> render_click()

      assert html =~ "Stop recording"
      assert ExNVR.Devices.get!(device.id).state == :recording
    end
  end
end
