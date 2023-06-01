defmodule ExNVR.Utils do
  @moduledoc false

  @spec recording_dir(binary()) :: Path.t()
  def recording_dir(device_id \\ nil) do
    dir = Application.get_env(:ex_nvr, :recording_directory)
    if device_id, do: Path.join(dir, device_id), else: dir
  end
end
