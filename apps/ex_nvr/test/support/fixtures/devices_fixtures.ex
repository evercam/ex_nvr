defmodule ExNVR.DevicesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ExNVR.Devices` context.
  """

  def valid_rtsp_url(), do: "rtsp://example#{System.unique_integer()}:8541"

  def valid_device_attributes(attrs \\ %{}) do
    {camera_config, attrs} = Map.pop(attrs, :ip_camera_config, %{})

    ip_camera_config =
      Enum.into(camera_config, %{
        stream_uri: "rtsp://localhost:554/my_device_stream",
        username: "user",
        password: "pass"
      })

    Enum.into(attrs, %{
      id: UUID.uuid4(),
      name: "Device_#{System.unique_integer([:monotonic, :positive])}",
      type: "IP",
      timezone: "UTC",
      state: :recording,
      ip_camera_config: ip_camera_config
    })
  end

  def device_fixture(attrs \\ %{}) do
    {:ok, device} =
      attrs
      |> valid_device_attributes()
      |> ExNVR.Devices.create()

    device
  end
end
