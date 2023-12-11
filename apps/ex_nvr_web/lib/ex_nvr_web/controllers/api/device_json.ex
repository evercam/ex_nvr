defmodule ExNVRWeb.API.DeviceJSON do
  @moduledoc false

  @spec show(map()) :: map()
  def show(%{device: device, user: user}) do
    serialize_device(user, device)
  end

  def list(%{devices: devices, user: user}) do
    Enum.map(devices, &serialize_device(user, &1))
  end

  defp serialize_device(user, device) do
    case user.role do
      :user ->
        device
        |> Map.take([:id, :name, :type, :state, :timezone])

      :admin ->
        device
        |> Map.from_struct()
        |> Map.drop([:__meta__])
        |> Map.put(:stream_config, Map.from_struct(device.stream_config))
        |> Map.put(:credentials, Map.from_struct(device.credentials))
        |> Map.put(:settings, Map.from_struct(device.settings))
    end
  end
end
