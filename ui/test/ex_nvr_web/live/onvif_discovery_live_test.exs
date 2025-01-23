defmodule ExNVRWeb.OnvifDiscoveryLiveTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.AccountsFixtures
  import Mimic
  import Phoenix.LiveViewTest

  alias Onvif.Devices.Schemas.{NetworkInterface, SystemDateAndTime}
  alias Onvif.Discovery.Probe
  alias Onvif.Media.Ver20.Schemas.Profile

  @probes [
    %Probe{
      types: ["dn:NetworkVideoTransmitter", "tds:Device"],
      scopes: [
        "onvif://www.onvif.org/Profile/Streaming",
        "onvif://www.onvif.org/name/Camera 1",
        "onvif://www.onvif.org/hardware/HW1"
      ],
      request_guid: "uuid:00000000-0000-0000-0000-000000000000",
      address: ["http://192.168.1.100/onvif/device_service"]
    },
    %Probe{
      types: ["dn:NetworkVideoTransmitter", "tds:Device"],
      scopes: [
        "onvif://www.onvif.org/Profile/Streaming",
        "onvif://www.onvif.org/name/Camera 2",
        "onvif://www.onvif.org/hardware/HW2"
      ],
      request_guid: "uuid:00000000-0000-0000-0000-000000000001",
      address: ["http://192.168.1.200/onvif/device_service"]
    }
  ]

  setup_all do
    Mimic.copy(Onvif.Devices.GetNetworkInterfaces)
    Mimic.copy(Onvif.Media.Ver20.GetProfiles)
    Mimic.copy(Onvif.Media.Ver20.GetStreamUri)
    Mimic.copy(Onvif.Media.Ver10.GetSnapshotUri)
    Mimic.copy(Onvif.Media.Ver20.GetVideoEncoderConfigurationOptions)
  end

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
    test "render found devices", %{conn: conn} do
      expect(Onvif.Discovery, :probe, fn _params -> @probes end)

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
  end

  describe "Render details" do
    setup do
      expect(Onvif.Discovery, :probe, fn _params -> Enum.take(@probes, 1) end)

      expect(Onvif.Device, :init, fn probe, "admin", "pass" ->
        {:ok,
         %Onvif.Device{
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

      expect(Onvif.Devices.GetNetworkInterfaces, :request, fn _device ->
        {:ok,
         [
           %NetworkInterface{
             info: %NetworkInterface.Info{name: "eth0"},
             ipv4: %NetworkInterface.IPv4{
               config: %NetworkInterface.IPv4.Config{
                 manual: %{address: "192.168.1.100"}
               }
             }
           }
         ]}
      end)

      expect(Onvif.Media.Ver20.GetProfiles, :request, fn _device ->
        {:ok,
         [
           %Profile{
             reference_token: "Profile_2",
             name: "subStream",
             video_encoder_configuration: %Profile.VideoEncoder{
               encoding: :h264,
               resolution: %Profile.VideoEncoder.Resolution{
                 width: 640,
                 height: 480
               },
               rate_control: %Profile.VideoEncoder.RateControl{
                 constant_bitrate: false,
                 bitrate_limit: 600
               }
             }
           },
           %Profile{
             reference_token: "Profile_1",
             name: "mainStream",
             video_encoder_configuration: %Profile.VideoEncoder{
               encoding: :h265,
               resolution: %Profile.VideoEncoder.Resolution{
                 width: 3840,
                 height: 2160
               },
               rate_control: %Profile.VideoEncoder.RateControl{
                 constant_bitrate: true,
                 bitrate_limit: 4096
               }
             }
           }
         ]}
      end)

      expect(Onvif.Media.Ver20.GetStreamUri, :request, fn _device, ["Profile_1"] ->
        {:ok, "rtsp://192.168.1.100:554/main"}
      end)
      |> expect(:request, fn _device, ["Profile_2"] ->
        {:ok, "rtsp://192.168.1.100:554/sub"}
      end)

      expect(Onvif.Media.Ver10.GetSnapshotUri, :request, fn _device, ["Profile_1"] ->
        {:ok, "http://192.168.1.100:8101/snapshot"}
      end)
      |> expect(:request, fn _device, ["Profile_2"] ->
        {:ok, "http://192.168.1.100:8101/sub"}
      end)

      expect(Onvif.Media.Ver20.GetVideoEncoderConfigurationOptions, :request, fn _device,
                                                                                 [
                                                                                   nil,
                                                                                   "Profile_1"
                                                                                 ] ->
        {:ok,
         [
           %Profile.VideoEncoderConfigurationOption{
             resolutions_available: [],
             encoding: :h265,
             gov_length_range: [1, 50],
             bitrate_range: %Profile.VideoEncoderConfigurationOption.BitrateRange{
               min: 10,
               max: 1000
             },
             quality_range: %Profile.VideoEncoderConfigurationOption.QualityRange{
               min: 1,
               max: 10
             }
           }
         ]}
      end)
      |> expect(:request, fn _device, [nil, "Profile_2"] ->
        {:ok,
         [
           %Profile.VideoEncoderConfigurationOption{
             resolutions_available: [],
             encoding: :h264,
             gov_length_range: [1, 25],
             bitrate_range: %Profile.VideoEncoderConfigurationOption.BitrateRange{
               min: 10,
               max: 100
             },
             quality_range: %Profile.VideoEncoderConfigurationOption.QualityRange{
               min: 1,
               max: 10
             }
           }
         ]}
      end)

      :ok
    end

    test "render device details", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onvif-discovery")

      lv
      |> form("#discover_form", %{discover_settings: %{username: "admin", password: "pass"}})
      |> render_submit()

      html = lv |> element("li[phx-click='device-details']") |> render_click()

      for term <- [
            "Evercam",
            "B11",
            "B11-DZ10",
            "CST-01:00",
            "mainStream",
            "subStream",
            "192.168.1.100",
            "rtsp://192.168.1.100:554/main",
            "rtsp://192.168.1.100:554/sub",
            "http://192.168.1.100:8101/snapshot",
            "h265",
            "h264",
            "3840 x 2160",
            "640 x 480"
          ] do
        assert html =~ term
      end
    end

    test "render cached device details", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onvif-discovery")

      lv |> form("#discover_form") |> render_submit()
      lv |> element("li[phx-click='device-details']") |> render_click()
      lv |> element("li[phx-click='device-details']") |> render_click()
    end

    test "redirect to add device form with discovred device details", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onvif-discovery")

      lv
      |> form("#discover_form", %{discover_settings: %{username: "admin", password: "pass"}})
      |> render_submit()

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
      assert device_params.stream_config.snapshot_uri == "http://192.168.1.100:8101/snapshot"
      assert device_params.vendor == "Evercam"
    end
  end
end
