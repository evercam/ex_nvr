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
        |> Map.from_struct()
        |> Map.drop([
          :__meta__,
          :stream_config,
          :credentials,
          :settings,
          :snapshot_config,
          :storage_config
        ])

      :admin ->
        device
        |> Map.from_struct()
        |> Map.drop([:__meta__])
        |> Map.put(:stream_config, to_map(device.stream_config))
        |> Map.put(:credentials, to_map(device.credentials))
        |> Map.put(:settings, to_map(device.settings))
        |> Map.put(:snapshot_config, to_map(device.snapshot_config))
        |> Map.put(:storage_config, to_map(device.storage_config))
    end
  end

  defp to_map(nil), do: nil
  defp to_map(struct), do: Map.from_struct(struct)
end
