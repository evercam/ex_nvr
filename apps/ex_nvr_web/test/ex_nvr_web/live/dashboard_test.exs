defmodule ExNVRWeb.DashboardTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures}
  import Phoenix.LiveViewTest

  describe "Dashboard page" do
    test "render dashboard page (no devices)", %{conn: conn} do
      {:ok, lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/dashboard")

      assert html =~ "You have no devices"

      {:error, redirect} = lv |> element("a", "here") |> render_click()

      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/devices"
    end

    test "render dashboard page (with devices)", %{conn: conn} do
      device_fixture()

      {:ok, lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/dashboard")

      assert html =~ "Device"
      assert html =~ "Start date"
      assert has_element?(lv, "#live-video")
    end
  end
end
