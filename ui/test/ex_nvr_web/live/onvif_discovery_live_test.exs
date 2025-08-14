defmodule ExNVRWeb.OnvifDiscoveryLiveTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.AccountsFixtures
  import Mimic
  import Phoenix.LiveViewTest

  alias ExOnvif.Devices.{NetworkInterface, SystemDateAndTime}
  alias ExOnvif.Discovery.Probe
  alias ExOnvif.Media.VideoResolution
  alias ExOnvif.Media2.{Profile, VideoEncoderConfigurationOption}

  @probes [
    %Probe{
      types: ["dn:NetworkVideoTransmitter", "tds:Device"],
      scopes: [
        "onvif://www.onvif.org/Profile/Streaming",
        "onvif://www.onvif.org/name/Camera 1",
        "onvif://www.onvif.org/hardware/HW1"
      ],
      request_guid: "uuid:00000000-0000-0000-0000-000000000000",
      address: ["http://192.168.1.100/onvif/device_service"],
      device_ip: "192.168.1.100"
    },
    %Probe{
      types: ["dn:NetworkVideoTransmitter", "tds:Device"],
      scopes: [
        "onvif://www.onvif.org/Profile/Streaming",
        "onvif://www.onvif.org/name/Camera 2",
        "onvif://www.onvif.org/hardware/HW2"
      ],
      request_guid: "uuid:00000000-0000-0000-0000-000000000001",
      address: ["http://192.168.1.200/onvif/device_service"],
      device_ip: "192.168.1.200"
    }
  ]

  setup_all do
    Mimic.copy(ExOnvif.Devices)
    Mimic.copy(ExOnvif.Media2)
  end

  setup %{conn: conn} do
    {:ok, conn: log_in_user(conn, user_fixture())}
  end

  test "render onvif discovery page", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/onvif-discovery")

    assert html =~ "Device Discovery"
    assert html =~ "Found 0 Device"
    assert html =~ "Network Settings"

    assert lv
           |> form("#discover_settings_form")
           |> has_element?()

    assert lv
           |> element("button", "Scan Network")
           |> has_element?()
  end

  test "Render found devices", %{conn: conn} do
    expect(ExOnvif.Discovery, :probe, fn _params -> @probes end)

    {:ok, lv, _html} = live(conn, ~p"/onvif-discovery")

    html =
      lv
      |> element("button", "Scan Network")
      |> render_click()

    assert html =~ "Found 2 Device(s)"

    assert html =~ "Camera 1"
    assert html =~ "192.168.1.100"
    assert lv |> element("#192\\.168\\.1\\.100 button") |> has_element?()

    assert html =~ "Camera 2"
    assert html =~ "192.168.1.200"
    assert lv |> element("#192\\.168\\.1\\.200 button") |> has_element?()
  end

  describe "Render details" do
    setup do
      expect(ExOnvif.Discovery, :probe, fn _params -> @probes end)

      expect(ExOnvif.Device, :init, fn probe, "admin", "pass" ->
        {:ok,
         %ExOnvif.Device{
           manufacturer: "Evercam",
           model: "B11",
           serial_number: "B11-DZ10",
           address: List.first(probe.address),
           scopes: probe.scopes,
           username: "admin",
           password: "pass",
           media_ver10_service_path: "/onvif/Media",
           media_ver20_service_path: "/onvif/Media2",
           system_date_time: %SystemDateAndTime{
             date_time_type: "Manual",
             daylight_savings: "true",
             time_zone: %SystemDateAndTime.TimeZone{tz: "CST-01:00"}
           }
         }}
      end)

      expect(ExOnvif.Devices, :get_network_interfaces, fn _device ->
        {:ok,
         [
           %NetworkInterface{
             info: %NetworkInterface.Info{name: "eth0", hw_address: "aa:bb:cc:00:11:22"},
             ipv4: %NetworkInterface.IPv4{
               enabled: true,
               config: %NetworkInterface.IPv4.Config{
                 dhcp: false,
                 manual: %{address: "192.168.1.200", prefix_length: 24}
               }
             }
           }
         ]}
      end)

      expect(ExOnvif.Media2, :get_profiles, fn _device ->
        {:ok,
         [
           %Profile{
             reference_token: "Profile_1",
             name: "mainStream",
             video_encoder_configuration: %Profile.VideoEncoder{
               encoding: :h265,
               resolution: %VideoResolution{width: 3840, height: 2160},
               rate_control: %Profile.VideoEncoder.RateControl{
                 constant_bitrate: true,
                 bitrate_limit: 4096
               }
             }
           },
           %Profile{
             reference_token: "Profile_2",
             name: "subStream",
             video_encoder_configuration: %Profile.VideoEncoder{
               encoding: :h264,
               resolution: %VideoResolution{width: 640, height: 480},
               rate_control: %Profile.VideoEncoder.RateControl{
                 constant_bitrate: false,
                 bitrate_limit: 600
               }
             }
           }
         ]}
      end)

      expect(ExOnvif.Media2, :get_stream_uri, fn _device, "Profile_2" ->
        {:ok, "rtsp://192.168.1.200:554/main"}
      end)
      |> expect(:get_stream_uri, fn _device, "Profile_1" ->
        {:ok, "rtsp://192.168.1.200:554/sub"}
      end)

      expect(ExOnvif.Media2, :get_snapshot_uri, fn _device, "Profile_2" ->
        {:ok, "http://192.168.1.200:8101/snapshot"}
      end)
      |> expect(:get_snapshot_uri, fn _device, "Profile_1" ->
        {:ok, "http://192.168.1.200:8101/sub"}
      end)

      expect(ExOnvif.Media2, :get_video_encoder_configuration_options, fn _device,
                                                                          profile_token:
                                                                            "Profile_1" ->
        {:ok,
         [
           %VideoEncoderConfigurationOption{
             resolutions_available: [],
             encoding: :h265,
             gov_length_range: [1, 50],
             bitrate_range: %ExOnvif.Schemas.IntRange{min: 10, max: 1000},
             quality_range: %ExOnvif.Schemas.FloatRange{min: 1, max: 10}
           }
         ]}
      end)
      |> expect(:get_video_encoder_configuration_options, fn _device,
                                                             profile_token: "Profile_2" ->
        {:ok,
         [
           %VideoEncoderConfigurationOption{
             resolutions_available: [],
             encoding: :h264,
             gov_length_range: [1, 25],
             bitrate_range: %ExOnvif.Schemas.IntRange{min: 10, max: 100},
             quality_range: %ExOnvif.Schemas.FloatRange{min: 1, max: 10}
           }
         ]}
      end)

      %{discover_params: %{discover_settings: %{username: "admin", password: "pass"}}}
    end

    test "authenticate device", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onvif-discovery")
      lv |> element("button", "Scan Network") |> render_click()

      auth_form = element(lv, "#auth-form")

      render_submit(auth_form, %{username: "admin", password: "pass", id: "192.168.1.200"})

      assert lv |> element("#192\\.168\\.1\\.100 button", "Authenticate") |> has_element?()
      refute lv |> element("#192\\.168\\.1\\.200 button", "Authenticate") |> has_element?()
      assert lv |> element("#192\\.168\\.1\\.200 button", "View Details") |> has_element?()

      expect(ExOnvif.Device, :init, 1, fn _probe, _user, _pass ->
        {:error, "Invalid Credentials"}
      end)

      html = render_submit(auth_form, %{username: "admin", password: "pass", id: "192.168.1.200"})
      assert html =~ "Invalid credentials"

      html = render_submit(auth_form, %{username: "admin", password: "pass", id: "192.168.1.2"})
      assert html =~ "could not find device with id"
    end

    test "Show device details", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onvif-discovery")
      lv |> element("button", "Scan Network") |> render_click()

      lv
      |> element("#auth-form")
      |> render_submit(%{username: "admin", password: "pass", id: "192.168.1.200"})

      html =
        lv
        |> element("#192\\.168\\.1\\.200 button", "View Details")
        |> render_click()

      assert has_element?(lv, "button", "Add to NVR")

      assert html =~ "Hardware Information"
      assert html =~ "Evercam"
      assert html =~ "B11"

      html = lv |> element("div span[phx-click]", "Network") |> render_click()

      assert html =~ "Network Configuration"
      assert html =~ "192.168.1.200"
      assert html =~ "aa:bb:cc:00:11:22"
      assert html =~ "Disabled"

      html = lv |> element("div span[phx-click]", "Date & Time") |> render_click()

      assert html =~ "Time Settings"
      assert html =~ "CST-01:00"

      html = lv |> element("div span[phx-click]", "Streams") |> render_click()

      assert html =~ "mainStream"
      assert html =~ "subStream"
      assert html =~ "3840x2160"
      assert html =~ "640x480"
      assert html =~ "rtsp://192.168.1.200:554/main"
      assert html =~ "rtsp://192.168.1.200:554/sub"
      assert html =~ "http://192.168.1.200:8101/snapshot"
      assert html =~ "H.265"
      assert html =~ "H.264"

      assert has_element?(lv, "#stream_selection_form")
    end

    test "Add to NVR", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onvif-discovery")
      lv |> element("button", "Scan Network") |> render_click()

      lv
      |> element("#auth-form")
      |> render_submit(%{username: "admin", password: "pass", id: "192.168.1.200"})

      lv
      |> element("#192\\.168\\.1\\.200 button", "View Details")
      |> render_click()

      {:ok, conn} =
        lv
        |> element("button", "Add to NVR")
        |> render_click()
        |> follow_redirect(conn, ~p"/devices/new")

      device_params = Phoenix.Flash.get(conn.assigns.flash, :device_params)
      assert device_params.name == "Camera 2"
      assert device_params.type == :ip
      assert device_params.stream_config.stream_uri == "rtsp://192.168.1.200:554/main"
      assert device_params.stream_config.snapshot_uri == "http://192.168.1.200:8101/snapshot"
      assert device_params.stream_config.sub_stream_uri == "rtsp://192.168.1.200:554/sub"
      assert device_params.stream_config.sub_snapshot_uri == "http://192.168.1.200:8101/sub"
      assert device_params.vendor == "Evercam"
    end
  end
end
