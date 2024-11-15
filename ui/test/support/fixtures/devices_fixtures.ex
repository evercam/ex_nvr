defmodule ExNVR.DevicesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ExNVR.Devices` context.
  """

  @spec valid_rtsp_url() :: binary()
  def valid_rtsp_url(), do: "rtsp://example#{System.unique_integer()}:8541"

  @spec valid_file_location() :: Path.t()
  def valid_file_location(), do: "../../fixtures/mp4/big_buck_avc.mp4" |> Path.expand(__DIR__)
  def invalid_file_extenstion(), do: "../../fixtures/video-30-10s.h264" |> Path.expand(__DIR__)

  @spec valid_device_name() :: binary()
  def valid_device_name(), do: "Device_#{System.unique_integer([:monotonic, :positive])}"

  @spec valid_device_credentials() :: map()
  def valid_device_credentials(), do: %{username: "user", password: "pass"}

  @spec valid_device_settings() :: map()
  def valid_device_settings(), do: %{generate_bif: false, storage_address: "/tmp"}

  def valid_device_storage_config(), do: %{address: "/tmp"}

  @spec valid_device_attributes(map(), binary()) :: map()
  def valid_device_attributes(attrs \\ %{}, type \\ :ip) do
    {stream_config, attrs} = Map.pop(attrs, :stream_config, %{})
    {storage_config, attrs} = Map.pop(attrs, :storage_config, %{})

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
      storage_config: Enum.into(storage_config, valid_device_storage_config()),
      snapshot_config: %{enabled: false}
    })
  end

  def camera_device_fixture(storage_address \\ "/tmp", attrs \\ %{}) do
    storage_config = Map.put(attrs[:storage_config] || %{}, :address, storage_address)

    {:ok, device} =
      attrs
      |> Map.put(:storage_config, storage_config)
      |> valid_device_attributes(:ip)
      |> ExNVR.Devices.create()

    device
  end

  def file_device_fixture(attrs \\ %{}) do
    {:ok, device} =
      attrs
      |> valid_device_attributes(:file)
      |> ExNVR.Devices.create()

    device
  end

  defp build_stream_config(stream_config, :ip) do
    Enum.into(stream_config, %{
      stream_uri: valid_rtsp_url()
    })
  end

  defp build_stream_config(stream_config, :file) do
    Enum.into(stream_config, %{
      filename: "big_buck.mp4",
      temporary_path: valid_file_location(),
      duration: 1000
    })
  end
end
