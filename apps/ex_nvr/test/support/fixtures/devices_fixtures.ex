defmodule ExNVR.DevicesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ExNVR.Devices` context.
  """

  def valid_rtsp_url(), do: "rtsp://example#{System.unique_integer()}:8541"

  def valid_file_location(), do: "/Dir/data/recordings/exampe#{System.unique_integer()}.mp4"

  def valid_device_attributes(attrs \\ %{}, type \\ :ip) do
    {camera_config, attrs} = Map.pop(attrs, :stream_config, %{})

    if type == :ip do
      credentials = %{
        username: "user",
        password: "pass"
      }

      stream_config =
        Enum.into(camera_config, %{
          stream_uri: "rtsp://localhost:554/my_device_stream"
        })

      Enum.into(attrs, %{
        id: UUID.uuid4(),
        name: "Device_#{System.unique_integer([:monotonic, :positive])}",
        type: "ip",
        timezone: "UTC",
        state: :recording,
        stream_config: stream_config,
        credentials: credentials
      })
    else
      stream_config =
        Enum.into(camera_config, %{
          location:
            "/ex_nvr/data/recordings/3f81d8b2-f288-4f61-8c71-404d228a5f6b/1693825914151636.mp4"
        })

      Enum.into(attrs, %{
        id: UUID.uuid4(),
        name: "Device_#{System.unique_integer([:monotonic, :positive])}",
        type: "file",
        timezone: "UTC",
        state: :recording,
        stream_config: stream_config
      })
    end
  end

  def device_fixture(attrs \\ %{}, device_type \\ :ip) do
    {:ok, device} =
      attrs
      |> valid_device_attributes(device_type)
      |> ExNVR.Devices.create()

    device
  end
end
