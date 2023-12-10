defmodule ExNVRWeb.OnvifDiscoveryLiveTest do
  @moduledoc false

  use ExNVRWeb.ConnCase

  import ExNVR.AccountsFixtures
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
         call!: fn
           "http://192.168.1.100/onvif/device_service", :get_capabilities ->
             capabilities_response_mock()
         end,
         call!: fn
           "http://192.168.1.100/onvif/Media", :get_stream_uri, _body, _opts ->
             stream_uri_response()
         end,
         call: fn
           "http://192.168.1.100/onvif/device_service", :get_device_information, _body, _opts ->
             device_information_response_mock()

           "http://192.168.1.100/onvif/device_service", :get_network_interfaces, _body, _opts ->
             network_interfaces_response_mock()

           "http://192.168.1.100/onvif/Media", :get_profiles, _body, _opts ->
             profiles_response_mock()

           "http://192.168.1.100/onvif/Media", :get_snapshot_uri, _body, _opts ->
             snapshot_uri_response_mock()
         end,
         call: fn "http://192.168.1.100/onvif/device_service", :get_system_date_and_time ->
           date_time_response_mock()
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

      assert_called_exactly(Onvif.call!(:_, :_, :_, :_), 2)
      assert_called_exactly(Onvif.call!(:_, :_), 1)
      assert_called_exactly(Onvif.call(:_, :_, :_, :_), 4)
      assert_called_exactly(Onvif.call(:_, :_), 1)
    end

    test "render cached device details", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onvif-discovery")

      lv |> form("#discover_form") |> render_submit()
      lv |> element("li[phx-click='device-details']") |> render_click()
      lv |> element("li[phx-click='device-details']") |> render_click()

      assert_called_exactly(Onvif.call!(:_, :_, :_, :_), 2)
      assert_called_exactly(Onvif.call!(:_, :_), 1)
      assert_called_exactly(Onvif.call(:_, :_, :_, :_), 4)
      assert_called_exactly(Onvif.call(:_, :_), 1)
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
    end
  end

  defp capabilities_response_mock() do
    %{
      GetCapabilitiesResponse: %{
        Capabilities: %{
          Media: %{
            XAddr: "http://192.168.1.100/onvif/Media"
          }
        }
      }
    }
  end

  defp date_time_response_mock() do
    {:ok,
     %{
       GetSystemDateAndTimeResponse: %{
         SystemDateAndTime: %{
           DateTimeType: "Manual",
           DaylightSavings: "true",
           TimeZone: %{
             TZ: "CST-01:00"
           }
         }
       }
     }}
  end

  defp device_information_response_mock() do
    {:ok,
     %{
       GetDeviceInformationResponse: %{
         Manufacturer: "Evercam",
         Model: "B11",
         SerialNumber: "B11-DZ10"
       }
     }}
  end

  defp network_interfaces_response_mock() do
    {:ok,
     %{
       GetNetworkInterfacesResponse: %{
         NetworkInterfaces: %{
           token: "eth0",
           IPv4: %{
             Config: %{
               DHCP: "false",
               Manual: %{Address: "192.168.1.100", PrefixLength: "24"}
             },
             Enabled: "true"
           },
           Info: %{Name: "eth0", HwAddress: "08:a1:89:e1:70:69", MTU: "1500"},
           Link: %{
             AdminSettings: %{AutoNegotiation: "true", Speed: "100", Duplex: "Full"},
             OperSettings: %{AutoNegotiation: "true", Speed: "100", Duplex: "Full"},
             InterfaceType: "0"
           },
           Enabled: "true"
         }
       }
     }}
  end

  defp profiles_response_mock() do
    {:ok,
     %{
       GetProfilesResponse: [
         Profiles: %{
           token: "Profile_1",
           Name: "mainStream",
           Configurations: %{
             VideoEncoder: %{
               token: "VideoEncoderToken_1",
               Name: "VideoEncoder_1",
               Resolution: %{Width: "3840", Height: "2160"},
               RateControl: %{
                 ConstantBitRate: "false",
                 FrameRateLimit: "8.000000",
                 BitrateLimit: "5120"
               },
               Encoding: "H265",
               Profile: "Main",
               GovLength: "25",
               Quality: "3.000000",
               UseCount: "1",
               Multicast: %{
                 Port: "8860",
                 Address: %{Type: "IPv4", IPv4Address: "0.0.0.0"},
                 TTL: "128",
                 AutoStart: "false"
               }
             },
             VideoSource: %{
               token: "VideoSourceToken",
               Name: "VideoSourceConfig",
               UseCount: "2",
               SourceToken: "VideoSource_1",
               Bounds: %{width: "3840", y: "0", x: "0", height: "2160"}
             }
           },
           fixed: "true"
         },
         Profiles: %{
           token: "Profile_2",
           Name: "subStream",
           Configurations: %{
             VideoEncoder: %{
               token: "VideoEncoderToken_2",
               Name: "VideoEncoder_2",
               Resolution: %{Width: "640", Height: "480"},
               RateControl: %{
                 ConstantBitRate: "false",
                 FrameRateLimit: "8.000000",
                 BitrateLimit: "768"
               },
               Encoding: "H265",
               Profile: "Main",
               GovLength: "50",
               Quality: "3.000000",
               UseCount: "1",
               Multicast: %{
                 Port: "8866",
                 Address: %{Type: "IPv4", IPv4Address: "0.0.0.0"},
                 TTL: "128",
                 AutoStart: "false"
               }
             },
             VideoSource: %{
               token: "VideoSourceToken",
               Name: "VideoSourceConfig",
               UseCount: "2",
               SourceToken: "VideoSource_1",
               Bounds: %{width: "3840", y: "0", x: "0", height: "2160"}
             }
           },
           fixed: "true"
         }
       ]
     }}
  end

  defp stream_uri_response() do
    %{GetStreamUriResponse: %{Uri: "rtsp://192.168.1.100:554/main"}}
  end

  defp snapshot_uri_response_mock() do
    {:ok, %{GetSnapshotUriResponse: %{Uri: "http://192.168.1.100:80/snapshot"}}}
  end
end
