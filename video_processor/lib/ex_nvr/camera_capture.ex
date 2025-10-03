defmodule ExNVR.AV.CameraCapture do
  @moduledoc false
  alias ExNVR.AV.CameraCapture.NIF
  @type native() :: reference()

  @spec open_camera(String.t(), String.t()) :: {:ok, native()} | {:error, term()}
  def open_camera(device_url, framerate) do
    NIF.open_camera(device_url, framerate)
  end

  @spec read_camera_frame(native()) :: {:ok, binary()} | {:error, term()}
  def read_camera_frame(native) do
    NIF.read_camera_frame(native)
  end

  # stream various properties of a
  @spec camera_stream_props(native()) :: {:ok, tuple()} | {:error, term()}
  def camera_stream_props(native) do
    NIF.camera_stream_props(native)
  end
end
