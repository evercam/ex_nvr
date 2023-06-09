defmodule ExNVRWeb.API.DeviceJSON do
  @moduledoc false

  alias ExNVR.Model.Device

  @spec show(Device.t()) :: map()
  def show(%{device: device}) do
    device
    |> Map.take([:id, :name, :type, :inserted_at, :updated_at])
    |> Map.put(:ip_camera_config, Map.from_struct(device.ip_camera_config))
  end
end
