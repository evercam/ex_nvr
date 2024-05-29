defmodule ExNVR.Devices.CameraClient do
  alias ExNVR.Devices.CameraClient.{Axis, Hik, Milesight}
  alias ExNVR.Model.Device

  @spec fetch_lpr_event(Device.t(), DateTime.t() | nil) ::
          {:ok, [map()], [binary() | nil]} | {:error, term()}
  def fetch_lpr_event(device, last_event_timestamp \\ nil) do
    with {:ok, {url, opts}} <- url_and_opts(device) do
      opts = opts ++ [last_event_timestamp: last_event_timestamp, timezone: device.timezone]

      vendor = Device.vendor(device)
      camera_module!(vendor).fetch_lpr_event(url, opts)
    end
  end

  @spec device_info(Device.t()) :: {:ok, map()} | {:error, any()}
  def device_info(device) do
    with {:ok, module} <- camera_module(Device.vendor(device)),
         {:ok, {url, opts}} <- url_and_opts(device) do
      module.device_info(url, opts)
    end
  end

  @spec get_stream_config(Device.t()) :: {:ok, map()} | {:error, any()}
  def get_stream_config(device) do
    with {:ok, module} <- camera_module(Device.vendor(device)),
         {:ok, {url, opts}} <- url_and_opts(device) do
      module.get_stream_config(url, opts)
    end
  end

  defp camera_module(:axis), do: {:ok, Axis}
  defp camera_module(:hik), do: {:ok, Hik}
  defp camera_module(:milesight), do: {:ok, Milesight}
  defp camera_module(_vendor), do: {:error, :not_implemented}

  defp camera_module!(vendor) do
    case camera_module(vendor) do
      {:ok, module} ->
        module

      _error ->
        raise "Not implementation module is found for #{inspect(vendor)}"
    end
  end

  defp url_and_opts(%{url: nil}), do: {:error, :url_not_configured}

  defp url_and_opts(device) do
    %{username: username, password: password} = device.credentials
    auth_type = if not is_nil(username) && not is_nil(password), do: :basic
    http_url = Device.http_url(device)

    opts =
      [
        username: username,
        password: password,
        auth_type: auth_type
      ]

    {:ok, {http_url, opts}}
  end
end
