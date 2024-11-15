defmodule ExNVRWeb.DashboardTest do
  @moduledoc false
  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, DevicesFixtures, RecordingsFixtures}
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  describe "Dashboard page" do
    test "render dashboard page (no devices)", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/dashboard")

      assert html =~ "You have no devices"

      {:error, redirect} = lv |> element("a", "here") |> render_click()

      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/devices"
    end

    @tag :tmp_dir
    @tag :device
    test "render dashboard page (with devices)", %{conn: conn} do
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
    @describetag :tmp_dir

    test "switch devices update available streams", %{conn: conn, tmp_dir: tmp_dir} do
      device_1 = camera_device_fixture(tmp_dir)

      device_2 =
        camera_device_fixture(tmp_dir, %{
          stream_config: %{sub_stream_uri: valid_rtsp_url()}
        })

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
    @describetag :tmp_dir
    @describetag :device

    test "end date field is shown if custom duration selected", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard")

      html =
        lv
        |> element("#footage_duration")
        |> render_change(%{footage: %{duration: ""}})

      assert html =~ "End Date"
    end

    test "no footage", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard")

      html =
        lv
        |> form("#footage_form")
        |> render_submit(%{footage: %{start_date: "2023-10-05T10:00"}})

      assert html =~ "No recordings found"
      refute html =~ "End Date"
    end

    test "no errors", %{conn: conn, device: device} do
      recording_fixture(device, start_date: ~U(2023-10-05T10:00:00Z))

      {:ok, lv, _html} = live(conn, ~p"/dashboard")

      html =
        lv
        |> form("#footage_form")
        |> render_submit(%{footage: %{start_date: "2023-10-05T10:00"}})

      refute html =~ "No recordings found"
    end
  end
end
