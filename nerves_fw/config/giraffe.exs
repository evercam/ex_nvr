import Config

config :nerves, :firmware, fwup_conf: "giraffe/fwup.conf"

config :nerves_time,
  rtc: {ExNVR.Nerves.Giraffe.RTC.NervesTime, bus_name: "i2c-1"}
