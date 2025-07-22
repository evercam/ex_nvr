defmodule ExNvrWeb.DeviceDetailsLiveTest do
  use ExNVRWeb.ConnCase

  import ExNVR.AccountsFixtures
  import Phoenix.LiveViewTest

  @moduletag :tmp_dir

  describe "Device details page" do
    setup ctx do
      %{
        device: camera_device_fixture(ctx.tmp_dir),
        tabs: ["details", "recordings", "stats", "settings", "events"]
      }
    end

    test "render device details page", %{conn: conn, device: device, tabs: tabs} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details")

      assert has_element?(lv, "h2", "Device: #{device.name}")

      # check tabs
      tabs
      |> Enum.map(fn tab ->
        assert lv
               |> element(~s|[id="tab-#{tab}"]|)
               |> has_element?()
      end)
    end

    test "Changing tabs by clicking on tabs", %{conn: conn, device: device, tabs: tabs} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details")

      for tab <- tabs do
        element = element(lv, "[phx-click='switch_tab'][phx-value-tab='#{tab}']")
        assert has_element?(element)

        _html = render_click(element)

        assert element(lv, "#tab-#{tab}[aria-selected='true']") |> has_element?()
      end
    end

    test "Stop device recording on settings tab", %{conn: conn, tmp_dir: tmp_dir} do
      device = camera_device_fixture(tmp_dir, %{state: :recording})

      {:ok, lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details?tab=settings")

      assert html =~ "Stop recording"

      html =
        lv
        |> element(~s|a|, "Stop recording")
        |> render_click()

      assert html =~ "Start recording"

      assert ExNVR.Devices.get!(device.id).state == :stopped
    end

    test "Start device recording on settings tab", %{conn: conn, tmp_dir: tmp_dir} do
      device = camera_device_fixture(tmp_dir, %{state: :stopped})

      {:ok, lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details?tab=settings")

      assert html =~ "Start recording"

      html =
        lv
        |> element(~s|a|, "Start recording")
        |> render_click()

      assert html =~ "Stop recording"

      assert ExNVR.Devices.get!(device.id).state == :recording
    end

    test "Update device on settings tab", %{conn: conn, device: device} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/devices/#{device.id}/details?tab=settings")

      {:error, redirect} =
        lv
        |> element(~s|a|, "Update")
        |> render_click()

      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/devices/#{device.id}"
    end
  end
end
