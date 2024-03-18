defmodule ExNVR.Devices.Client do
  alias ExNVR.Devices.Client.{Axis, Hik, Milesight}

  def fetch_anpr(device, last_event_timestamp \\ nil) do
    opts = [
      username: device.credentials.username,
      password: device.credentials.password,
      last_event_timestamp: last_event_timestamp,
      timezone: device.timezone
    ]

    impl(device).fetch_anpr(device.url, opts)
  end

  defp impl(%{vendor: "AXIS"}), do: Axis
  defp impl(%{vendor: "HIKVISION"}), do: Hik
  defp impl(%{vendor: "Milesight Technology Co.,Ltd."}), do: Milesight
end
