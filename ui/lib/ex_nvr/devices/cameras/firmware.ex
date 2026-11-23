defmodule ExNVR.Devices.Cameras.Firmware do
  @moduledoc false

  alias ExNVR.{HTTP, RemoteConnection}

  @type t :: %__MODULE__{version: String.t(), url: String.t(), sha256: String.t()}

  @enforce_keys [:version, :url, :sha256]
  defstruct @enforce_keys

  @request_timeout to_timeout(second: 15)

  @doc """
  Check if firmwares can be fetched, they're assigned by the remote server.
  """
  @spec available?() :: boolean()
  def available?, do: not is_nil(Process.whereis(RemoteConnection))

  @doc """
  Get the firmware the remote server assigned to the camera, `nil` if none.
  """
  @spec assigned(map()) :: {:ok, t() | nil} | {:error, term()}
  def assigned(camera_info) do
    case RemoteConnection.push_and_wait("camera-firmware", camera_info, @request_timeout) do
      {:ok, reply} when reply == %{} ->
        {:ok, nil}

      {:ok, %{"version" => version, "url" => url, "sha256" => sha256}}
      when is_binary(version) and is_binary(url) and is_binary(sha256) ->
        {:ok, %__MODULE__{version: version, url: url, sha256: String.downcase(sha256)}}

      {:ok, reply} ->
        {:error, {:invalid_reply, reply}}

      error ->
        error
    end
  end

  @doc """
  Download the firmware, files already downloaded are reused.
  """
  @spec download(t(), Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def download(%__MODULE__{} = firmware, dir \\ default_dir()) do
    path = Path.join(dir, firmware.sha256)

    if valid_file?(path, firmware.sha256) do
      {:ok, path}
    else
      File.mkdir_p!(dir)
      remove_old_files(dir)
      do_download(firmware, path)
    end
  end

  defp do_download(firmware, path) do
    tmp_path = path <> ".part"

    with {:ok, %{status: 200}} <- HTTP.download(firmware.url, tmp_path),
         true <- valid_file?(tmp_path, firmware.sha256),
         :ok <- File.rename(tmp_path, path) do
      {:ok, path}
    else
      {:ok, %{status: status}} -> cleanup(tmp_path, {:error, {:download_failed, status}})
      false -> cleanup(tmp_path, {:error, :checksum_mismatch})
      error -> cleanup(tmp_path, error)
    end
  end

  defp valid_file?(path, sha256) do
    File.exists?(path) and
      path
      |> File.stream!(65_536)
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)
      |> Kernel.==(sha256)
  end

  # keep only one firmware on disk, partial files may be other downloads in progress
  defp remove_old_files(dir) do
    dir
    |> File.ls!()
    |> Enum.reject(&String.ends_with?(&1, ".part"))
    |> Enum.each(&File.rm(Path.join(dir, &1)))
  end

  defp cleanup(path, result) do
    File.rm(path)
    result
  end

  defp default_dir, do: Path.join(System.tmp_dir!(), "camera_firmware")
end
