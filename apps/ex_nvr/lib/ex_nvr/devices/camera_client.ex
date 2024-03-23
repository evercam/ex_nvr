defmodule ExNVR.Devices.CameraClient do
  alias ExNVR.Devices.CameraClient.{Axis, Hik, Milesight}
  alias ExNVR.Model.Device

  def fetch_anpr(device, last_event_timestamp \\ nil) do
    opts =
      [
        username: device.credentials.username,
        password: device.credentials.password,
        last_event_timestamp: last_event_timestamp,
        timezone: device.timezone
      ] ++ Device.auth_type(device)

    vendor = Device.vendor(device)
    base_url = Device.base_url(device)

    impl(vendor).fetch_anpr(base_url, opts)
  end

  defp impl(:axis), do: Axis
  defp impl(:hik), do: Hik
  defp impl(:milesight), do: Milesight
end
