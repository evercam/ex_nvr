defmodule ExNVR.Onvif.TestUtils do
  @moduledoc false

  def capabilities_response_mock() do
    {:ok,
     %{
       media: %{
         x_addr: "http://192.168.1.100/onvif/Media"
       }
     }}
  end

  def date_time_response_mock() do
    {:ok,
     %{
       date_time_type: "Manual",
       daylight_savings: "true",
       time_zone: %{
         tz: "CST-01:00"
       }
     }}
  end

  def device_information_response_mock() do
    {:ok,
     %{
       manufacturer: "Evercam",
       model: "B11",
       serial_number: "B11-DZ10"
     }}
  end

  def network_interfaces_response_mock() do
    {:ok,
     [
       %{
         token: "eth0",
         ip_v4: %{
           config: %{
             dhcp: "false",
             manual: %{address: "192.168.1.100", prefix_length: "24"}
           },
           enabled: "true"
         },
         info: %{name: "eth0", hw_address: "08:a1:89:e1:70:69", mtu: "1500"},
         link: %{
           admin_settings: %{auto_negotiation: "true", speed: "100", duplex: "Full"},
           oper_settings: %{auto_negotiation: "true", speed: "100", duplex: "Full"},
           interface_type: "0"
         },
         enabled: "true"
       }
     ]}
  end

  def profiles_response_mock() do
    {:ok,
     [
       %{
         token: "Profile_1",
         id: "mainStream",
         enabled: true,
         name: "mainStream",
         codec: "H265",
         profile: "Main",
         width: "3840",
         height: "2160",
         frame_rate: "8.000000",
         bitrate: "5120",
         gop: "25"
       },
       %{
         token: "Profile_2",
         id: "subStream",
         enabled: true,
         name: "subStream",
         codec: "H265",
         profile: "Main",
         width: "640",
         height: "480",
         frame_rate: "8.000000",
         bitrate: "768",
         gop: "50"
       }
     ]}
  end

  def stream_uri_response(), do: "rtsp://192.168.1.100:554/main"
  def snapshot_uri_response_mock(), do: "http://192.168.1.100:80/snapshot"
end
