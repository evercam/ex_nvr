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

      assert html =~ "Add Device"
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

    test "redirect clicking on the device", %{conn: conn, device: device} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices")

      {:error, redirect} =
        lv
        |> element(~s|[id="device-row-#{device.id}"] td:first-child|)
        |> render_click()

      assert {:live_redirect, %{to: path}} = redirect
      assert path =~ ~p"/devices/#{device.id}/details"
    end
  end
end
