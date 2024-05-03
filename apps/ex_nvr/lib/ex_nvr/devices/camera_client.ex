defmodule ExNVR.Devices.CameraClient do
  alias ExNVR.Devices.CameraClient.{Axis, Hik, Milesight}
  alias ExNVR.Model.Device

  @spec fetch_lpr_event(Device.t(), DateTime.t() | nil) ::
          {:ok, [map()], [binary() | nil]} | {:error, term()}
  def fetch_lpr_event(device, last_event_timestamp \\ nil) do
    %{username: username, password: password} = device.credentials
    auth_type = if not is_nil(username) && not is_nil(password), do: :basic

    opts =
      [
        username: username,
        password: password,
        auth_type: auth_type,
        last_event_timestamp: last_event_timestamp,
        timezone: device.timezone
      ]

    vendor = Device.vendor(device)
    http_url = Device.http_url(device)

    impl(vendor).fetch_lpr_event(http_url, opts)
  end

  defp impl(:axis), do: Axis
  defp impl(:hik), do: Hik
  defp impl(:milesight), do: Milesight
end
