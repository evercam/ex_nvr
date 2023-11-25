defmodule ExNVR.Upgrade do
  @moduledoc """
  Set of functions to upgrade to a new version after introducing breaking changes
  """

  require Logger

  alias ExNVR.Model.{Device, Recording}

  @app :ex_nvr

  @spec upgrade(binary(), Keyword.t()) :: :ok
  def upgrade(version, opts \\ []) do
    Application.load(@app)
    do_upgrade(version, opts)
  end

  defp do_upgrade("v0.6.0", opts) do
    mountpoint = Keyword.fetch!(opts, :mountpoint)
    recording_dir = Keyword.fetch!(opts, :recording_dir)

    ExNVR.Repo.update_all(Device, set: [settings: %Device.Settings{storage_address: mountpoint}])
    devices = ExNVR.Repo.all(Device)

    Enum.each(devices, &create_device_directories/1)
    Enum.each(devices, &do_migrate_recordings(&1, recording_dir))
  end

  defp create_device_directories(device) do
    File.mkdir_p!(Device.base_dir(device))
    File.mkdir_p!(Device.recording_dir(device))
    File.mkdir_p!(Device.recording_dir(device, :low))
    File.mkdir_p!(Device.bif_dir(device))
  end

  defp do_migrate_recordings(device, recording_dir) do
    Logger.info("Migrate device recordings: #{device.id}")

    bif_dir = Path.join([recording_dir, device.id, "bif"])

    Path.join(bif_dir, "*.bif")
    |> Path.wildcard()
    |> Enum.each(fn filename ->
      File.rename!(filename, Path.join(Device.bif_dir(device), Path.basename(filename)))
    end)

    stream = ExNVR.Repo.stream(Recording.with_device(device.id), timeout: :infinity)

    ExNVR.Repo.transaction(fn ->
      stream
      |> Stream.map(fn recording ->
        src = Path.join([recording_dir, device.id, recording.filename])
        dest = ExNVR.Recordings.recording_path(device, recording)

        if File.exists?(src) do
          File.mkdir_p!(Path.dirname(dest))
          File.rename!(src, dest)
        end
      end)
      |> Stream.run()
    end)
  end
end
