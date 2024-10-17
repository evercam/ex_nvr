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
         name: "mainStream",
         configurations: %{
           video_encoder: %{
             token: "VideoEncoderToken_1",
             name: "VideoEncoder_1",
             resolution: %{width: "3840", height: "2160"},
             rate_control: %{
               constant_bit_rate: "false",
               frame_rate_limit: "8.000000",
               bitrate_limit: "5120"
             },
             encoding: "H265",
             profile: "Main",
             gov_length: "25",
             quality: "3.000000",
             use_count: "1",
             multicast: %{
               port: "8860",
               address: %{type: "IPv4", ip_v4_address: "0.0.0.0"},
               ttl: "128",
               auto_start: "false"
             }
           },
           video_source: %{
             token: "VideoSourceToken",
             name: "VideoSourceConfig",
             use_count: "2",
             source_token: "VideoSource_1",
             bounds: %{width: "3840", y: "0", x: "0", height: "2160"}
           }
         },
         fixed: "true"
       },
       %{
         token: "Profile_2",
         name: "subStream",
         configurations: %{
           video_encoder: %{
             token: "VideoEncoderToken_2",
             name: "VideoEncoder_2",
             resolution: %{width: "640", height: "480"},
             rate_control: %{
               constant_bit_rate: "false",
               frame_rate_limit: "8.000000",
               bitrate_limit: "768"
             },
             encoding: "H265",
             profile: "Main",
             gov_length: "50",
             quality: "3.000000",
             use_count: "1",
             multicast: %{
               port: "8866",
               address: %{type: "IPv4", ip_v4_address: "0.0.0.0"},
               ttl: "128",
               auto_start: "false"
             }
           },
           video_source: %{
             token: "VideoSourceToken",
             name: "VideoSourceConfig",
             use_count: "2",
             source_token: "VideoSource_1",
             bounds: %{width: "640", y: "0", x: "0", height: "480"}
           }
         },
         fixed: "true"
       }
     ]}
  end

  def stream_uri_response(), do: "rtsp://192.168.1.100:554/main"
  def snapshot_uri_response_mock(), do: "http://192.168.1.100:80/snapshot"
end
