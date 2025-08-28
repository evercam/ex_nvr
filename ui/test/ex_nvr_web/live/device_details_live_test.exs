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

      assert has_element?(lv, "h2", "#{device.name}")

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
  end
end
