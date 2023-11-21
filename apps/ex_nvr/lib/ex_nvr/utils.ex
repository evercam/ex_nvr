defmodule ExNVR.Utils do
  @moduledoc false

  alias ExNVR.Model.Device

  @unix_socket_dir "/tmp/sockets"

  @spec recording_dir(Device.t()) :: Path.t()
  def recording_dir(device) do
    case Device.recording_dir(device) do
      nil ->
        dir = Application.get_env(:ex_nvr, :recording_directory)
        Path.join(dir, device.id)

      path ->
        path
    end
  end

  @spec hls_dir(Device.id() | nil) :: Path.t()
  def hls_dir(device_id \\ nil) do
    dir = Application.get_env(:ex_nvr, :hls_directory)
    if device_id, do: Path.join(dir, device_id), else: dir
  end

  @spec bif_dir(Device.t()) :: Path.t()
  def bif_dir(device) do
    Path.join(recording_dir(device), "bif")
  end

  @spec unix_socket_dir() :: Path.t()
  def unix_socket_dir(), do: @unix_socket_dir

  @spec unix_socket_path(Device.id()) :: Path.t()
  def unix_socket_path(device_id) do
    Path.join(@unix_socket_dir, "ex_nvr.#{device_id}.sock")
  end

  @spec pipeline_name(Device.t()) :: atom()
  def pipeline_name(device), do: :"pipeline_#{device.id}"

  @spec run_main_pipeline?() :: boolean()
  def run_main_pipeline?(), do: Application.get_env(:ex_nvr, :run_pipelines, true)

  @spec generate_token(non_neg_integer()) :: binary()
  def generate_token(token_len \\ 16),
    do: :crypto.strong_rand_bytes(token_len) |> Base.url_encode64()

  # Streaming & Codecs utilities
  defguard keyframe(buffer) when buffer.metadata.h264.key_frame?
end
