defmodule ExNVR.Utils do
  @moduledoc false

  alias ExNVR.Model.Device

  @unix_socket_dir "/tmp/sockets"

  @spec hls_dir(Device.id() | nil) :: Path.t()
  def hls_dir(device_id \\ nil) do
    dir = Application.get_env(:ex_nvr, :hls_directory)
    if device_id, do: Path.join(dir, device_id), else: dir
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

  @spec date_components(DateTime.t()) :: [binary()]
  def date_components(%DateTime{} = datetime) do
    [
      "#{datetime.year}",
      pad_number(datetime.month),
      pad_number(datetime.day),
      pad_number(datetime.hour)
    ]
  end

  defp pad_number(number), do: String.pad_leading("#{number}", 2, "0")

  @doc """
  Check if destination exists and writable
  """
  @spec writable(Path.t()) :: :ok | {:error, term()}
  def writable(dest) do
    touch_file = Path.join(dest, ".ex_nvr_check")

    case File.touch(touch_file) do
      :ok ->
        File.rm(touch_file)
        :ok

      error ->
        error
    end
  end

  # Streaming & Codecs utilities
  defguard keyframe(buffer)
           when (is_map_key(buffer.metadata, :h264) and buffer.metadata.h264.key_frame?) or
                  (is_map_key(buffer.metadata, :h265) and buffer.metadata.h265.key_frame?)
end
