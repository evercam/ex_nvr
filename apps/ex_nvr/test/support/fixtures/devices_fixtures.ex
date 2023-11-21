defmodule ExNVR.DevicesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ExNVR.Devices` context.
  """

  @spec valid_rtsp_url() :: binary()
  def valid_rtsp_url(), do: "rtsp://example#{System.unique_integer()}:8541"

  @spec valid_file_location() :: Path.t()
  def valid_file_location(), do: "../../fixtures/big_buck.mp4" |> Path.expand(__DIR__)
  def invalid_file_extenstion(), do: "../../fixtures/video-30-10s.h264" |> Path.expand(__DIR__)

  @spec valid_device_name() :: binary()
  def valid_device_name(), do: "Device_#{System.unique_integer([:monotonic, :positive])}"

  def valid_device_credentials(), do: %{username: "user", password: "pass"}
  def valid_device_settings(), do: %{generate_bif: false, storage_address: "/tmp"}

  def valid_device_attributes(attrs \\ %{}, type \\ "ip") do
    {stream_config, attrs} = Map.pop(attrs, :stream_config, %{})
    credentials = valid_device_credentials()
    stream_config = build_stream_config(stream_config, type)

    Enum.into(attrs, %{
      id: UUID.uuid4(),
      name: valid_device_name(),
      type: type,
      timezone: "UTC",
      state: :recording,
      stream_config: stream_config,
      credentials: credentials,
      settings: valid_device_settings()
    })
  end

  @spec device_fixture(map(), binary()) :: ExNVR.Model.Device.t()
  def device_fixture(attrs \\ %{}, device_type \\ "ip") do
    {:ok, device} =
      attrs
      |> valid_device_attributes(device_type)
      |> ExNVR.Devices.create()

    device
  end

  defp build_stream_config(stream_config, "ip") do
    Enum.into(stream_config, %{
      stream_uri: valid_rtsp_url()
    })
  end

  defp build_stream_config(stream_config, "file") do
    Enum.into(stream_config, %{
      location: valid_file_location()
    })
  end
end
