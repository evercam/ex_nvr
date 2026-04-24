import Config

config :nerves, :firmware, fwup_conf: "recomputer-r22/fwup.conf"

config :vintage_net,
  regulatory_domain: "00",
  config: [
    {"usb0", %{type: VintageNetDirect}},
    {"eth0",
     %{
       type: VintageNetEthernet,
       ipv4: %{method: :dhcp}
     }},
    {"usb1",
     %{
       type: VintageNetEthernet,
       ipv4: %{method: :dhcp}
     }},
    {"wlan0", %{type: VintageNetWiFi}},
    {"eth1",
     %{
       type: VintageNetEthernet,
       ipv4: %{method: :static, address: "192.168.2.200", prefix_length: 24}
     }},
    {"eth2",
     %{
       type: VintageNetEthernet,
       ipv4: %{method: :static, address: "192.168.3.200", prefix_length: 24}
     }},
    {"eth3",
     %{
       type: VintageNetEthernet,
       ipv4: %{method: :static, address: "192.168.4.200", prefix_length: 24}
     }},
    {"eth4",
     %{
       type: VintageNetEthernet,
       ipv4: %{method: :static, address: "192.168.5.200", prefix_length: 24}
     }}
  ]
