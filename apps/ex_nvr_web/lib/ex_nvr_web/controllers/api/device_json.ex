defmodule ExNVRWeb.API.DeviceJSON do
  @moduledoc false

  @spec show(map()) :: map()
  def show(%{device: device}) do
    device
    |> Map.take([:id, :name, :type, :state, :timezone, :inserted_at, :updated_at])
    |> Map.put(:stream_config, Map.from_struct(device.stream_config))
    |> Map.put(:credentials, Map.from_struct(device.credentials))
  end
end
