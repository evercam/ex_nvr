defmodule ExNVRWeb.API.DeviceJSON do
  @moduledoc false

  @spec show(map()) :: map()
  def show(%{device: device}) do
    serialize_device(device)
  end

  def list(%{devices: devices}) do
    Enum.map(devices, &serialize_device/1)
  end

  defp serialize_device(device) do
    device
    |> Map.take([:__meta__])
    |> Map.put(:stream_config, Map.from_struct(device.stream_config))
    |> Map.put(:credentials, Map.from_struct(device.credentials))
    |> Map.put(:settings, Map.from_struct(device.settings))
  end
end
