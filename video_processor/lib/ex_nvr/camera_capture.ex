defmodule ExNVR.AV.CameraCapture do
  @moduledoc false
  alias ExNVR.AV.VideoProcessor.NIF
  @type native() :: pid()

  @spec do_open(String.t(), String.t()) :: {:ok, native()} | {:error, term()}
  def do_open(device_url, framerate) do
    NIF.do_open(device_url, framerate)
  end

  @spec read_frame(native()) :: {:ok, binary()} | {:error, term()}
  def read_frame(native) do
    NIF.read_frame(native)
  end

  # stream various properties of a
  @spec stream_props(native()) :: {:ok, tuple()} | {:error, term()}
  def stream_props(native) do
    NIF.stream_props(native)
  end
end
