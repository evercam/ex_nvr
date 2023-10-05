defmodule ExNVRWeb.DashboardTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures}
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  describe "Dashboard page" do
    test "render dashboard page (no devices)", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/dashboard")

      assert html =~ "You have no devices"
      refute html =~ "Download"

      {:error, redirect} = lv |> element("a", "here") |> render_click()

      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/devices"
    end

    test "render dashboard page (with devices)", %{conn: conn} do
      device_fixture()

      {:ok, lv, html} = live(conn, ~p"/dashboard")

      assert html =~ "Device"
      assert html =~ "Stream"
      assert html =~ "Download"

      assert has_element?(lv, "#timeline")
      assert has_element?(lv, "#download-footage-btn")

      refute has_element?(lv, "#live-video")
    end
  end

  describe "switch device" do
    test "switch devices update available streams", %{conn: conn} do
      device_1 = device_fixture()
      device_2 = device_fixture(%{stream_config: %{sub_stream_uri: valid_rtsp_url()}})

      {:ok, lv, html} = live(conn, ~p"/dashboard")

      assert html =~ device_1.id
      assert html =~ device_2.id
      assert html =~ "main_stream"
      refute html =~ "sub_stream"

      html =
        lv
        |> element("#device_form_id")
        |> render_change(%{"device" => device_2.id})

      assert html =~ "main_stream"
      assert html =~ "sub_stream"
    end
  end

  describe "download footage" do
    test "show footage-download popup on clicked button", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/dashboard")

      assert lv
       |> element("#download-footage-btn")
       |> render_click() =~ "Download Footage"
    end
  end
end
