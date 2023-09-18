defmodule ExNVRWeb.API.DeviceJSON do
  @moduledoc false

  @spec show(map()) :: map()
  def show(%{device: device}) do
    device
    |> Map.take([:id, :name, :type, :state, :timezone, :inserted_at, :updated_at])
    |> Map.put(:stream_config, Map.from_struct(device.stream_config))
    |> Map.put(:credentials, Map.from_struct(device.credentials))
  end

  def list(%{devices: devices}) do
    Enum.map(devices, &transform_device/1)
  end

  defp transform_device(device) do
    device
    |> Map.take([:id, :name, :type, :state, :timezone, :inserted_at, :updated_at])
    |> Map.put(:ip_camera_config, Map.from_struct(device.ip_camera_config))
  end
end
