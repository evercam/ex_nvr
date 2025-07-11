defmodule ExNvrWeb.DeviceDetailsLiveTest do
  use ExNVRWeb.ConnCase

  import ExNVR.AccountsFixtures
  import Phoenix.LiveViewTest

  @moduletag :tmp_dir

  @doc """
    check list for this test

  1. check the rendering of that page
  2. check if the tabs are available
  3. check if the tabs contains the data needed
  4.  

  test the tab change feat
  test the details of each tab
  """
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

      tabs
      |> Enum.map(fn tab ->
        {:ok, new_html} =
          lv
          |> element(~s|[phx-click="switch_tab"][phx-value-tab=#{tab}]|)
          |> render_click()
          |> Floki.parse_document()

        # check switch tabs when click happens
        [{"li", attrs, _children}] =
          new_html
          |> Floki.find("#tab-#{tab}")

        {"aria-selected", value} = List.keyfind(attrs, "aria-selected", 0)
        assert value == "true"
      end)
    end
  end
end
