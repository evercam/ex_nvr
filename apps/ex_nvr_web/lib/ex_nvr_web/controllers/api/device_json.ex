defmodule ExNVRWeb.API.DeviceJSON do
  @moduledoc false

  def show(%{device: device}) do
    device
    |> Map.take([:id, :name, :type])
    |> Map.merge(Map.from_struct(device.ip_camera_config))
  end
end
