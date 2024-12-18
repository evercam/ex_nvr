defmodule ExNVRWeb.OnvifDiscoveryLiveTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.{AccountsFixtures, Onvif.TestUtils}
  import Mock
  import Phoenix.LiveViewTest

  alias ExNVR.Onvif

  setup %{conn: conn} do
    {:ok, conn: log_in_user(conn, user_fixture())}
  end

  test "render onvif discovery page", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/onvif-discovery")

    assert html =~ "Discover Devices"
    assert html =~ "Found Devices"
    assert html =~ "Device Details"

    assert lv
           |> form("#discover_form")
           |> has_element?()

    assert lv
           |> element("button", "Scan")
           |> has_element?()
  end

  describe "Discover devices" do
    setup_with_mocks([
      {ExNVR.Onvif, [],
       [
         discover: fn
           [timeout: 1000] ->
             {:ok,
              [
                %{
                  name: "Camera 1",
                  hardware: "HW1",
                  url: "http://192.168.1.100/onvif/device_service"
                },
                %{
                  name: "Camera 2",
                  hardware: "HW2",
                  url: "http://192.168.1.200/onvif/device_service"
                }
              ]}

           [timeout: 2000] ->
             {:error, "something is wrong"}
         end
       ]}
    ]) do
      :ok
    end

    test "render found devices", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onvif-discovery")

      html =
        lv
        |> form("#discover_form")
        |> render_submit(%{"discover_settings" => %{"timeout" => "1"}})

      assert html =~ "Camera 1"
      assert html =~ "HW1"
      assert html =~ "http://192.168.1.100/onvif/device_service"

      assert html =~ "Camera 2"
      assert html =~ "HW2"
      assert html =~ "http://192.168.1.200/onvif/device_service"
    end

    test "render validation errors", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onvif-discovery")

      html =
        lv
        |> form("#discover_form")
        |> render_submit(%{"discover_settings" => %{"timeout" => "0"}})

      refute html =~ "Camera 1"
      assert html =~ "is invalid"
    end

    test "render discovery errors as flash", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onvif-discovery")

      html =
        lv
        |> form("#discover_form")
        |> render_submit(%{"discover_settings" => %{"timeout" => "2"}})

      refute html =~ "Camera 1"
      refute html =~ "Camera 2"

      assert html =~ "Error occurred while discovering devices"
    end
  end

  describe "Render details" do
    @device_url "http://192.168.1.100/onvif/device_service"
    @media_url "http://192.168.1.100/onvif/Media"

    setup_with_mocks([
      {ExNVR.Onvif, [],
       [
         discover: fn _ ->
           {:ok,
            [
              %{
                name: "Camera 1",
                hardware: "HW1",
                url: "http://192.168.1.100/onvif/device_service"
              }
            ]}
         end,
         get_system_date_and_time: fn @device_url -> date_time_response_mock() end,
         get_device_information: fn @device_url, _opts -> device_information_response_mock() end,
         get_network_interfaces: fn @device_url, _opts -> network_interfaces_response_mock() end,
         get_capabilities: fn @device_url, _opts -> capabilities_response_mock() end,
         get_media_profiles: fn @media_url, _opts -> profiles_response_mock() end,
         get_media_stream_uri!: fn @media_url, _profile, _opts -> stream_uri_response() end,
         get_media_snapshot_uri!: fn @media_url, _profile, _opts ->
           snapshot_uri_response_mock()
         end
       ]}
    ]) do
      :ok
    end

    test "render device details", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onvif-discovery")

      lv |> form("#discover_form") |> render_submit()
      html = lv |> element("li[phx-click='device-details']") |> render_click()

      for term <- [
            "Evercam",
            "B11",
            "B11-DZ10",
            "Manual",
            "CST-01:00",
            "mainStream",
            "subStream",
            "192.168.1.100",
            "rtsp://192.168.1.100:554/main"
          ] do
        assert html =~ term
      end

      assert_called_exactly(Onvif.get_system_date_and_time(:_), 1)
      assert_called_exactly(Onvif.get_device_information(:_, :_), 1)
      assert_called_exactly(Onvif.get_network_interfaces(:_, :_), 1)
      assert_called_exactly(Onvif.get_capabilities(:_, :_), 1)
      assert_called_exactly(Onvif.get_media_profiles(:_, :_), 1)
      assert_called_exactly(Onvif.get_media_stream_uri!(:_, :_, :_), 2)
      assert_called_exactly(Onvif.get_media_snapshot_uri!(:_, :_, :_), 2)
    end

    test "render cached device details", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onvif-discovery")

      lv |> form("#discover_form") |> render_submit()
      lv |> element("li[phx-click='device-details']") |> render_click()
      lv |> element("li[phx-click='device-details']") |> render_click()

      assert_called_exactly(Onvif.get_system_date_and_time(:_), 1)
      assert_called_exactly(Onvif.get_device_information(:_, :_), 1)
      assert_called_exactly(Onvif.get_network_interfaces(:_, :_), 1)
      assert_called_exactly(Onvif.get_capabilities(:_, :_), 1)
      assert_called_exactly(Onvif.get_media_profiles(:_, :_), 1)
      assert_called_exactly(Onvif.get_media_stream_uri!(:_, :_, :_), 2)
      assert_called_exactly(Onvif.get_media_snapshot_uri!(:_, :_, :_), 2)
    end

    test "redirect to add device form with discovred device details", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onvif-discovery")

      lv |> form("#discover_form") |> render_submit()
      lv |> element("li[phx-click='device-details']") |> render_click()

      {:ok, conn} =
        lv
        |> element("button[phx-click='add-device']")
        |> render_click()
        |> follow_redirect(conn, ~p"/devices/new")

      device_params = Phoenix.Flash.get(conn.assigns.flash, :device_params)
      assert device_params.name == "Camera 1"
      assert device_params.type == :ip
      assert device_params.stream_config.stream_uri == "rtsp://192.168.1.100:554/main"
      assert device_params.stream_config.snapshot_uri == "http://192.168.1.100:80/snapshot"
      assert device_params.vendor == "Evercam"
    end
  end
end
