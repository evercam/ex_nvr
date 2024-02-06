defmodule ExNVR.SnapshotUploader do
  use GenServer

  require Logger

  alias ExNVR.Model.RemoteStorage
  alias ExNVR.{Devices, HTTP, RemoteStorages, S3}

  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  @impl true
  def init(options) do
    IO.inspect("wik")
    Logger.metadata(device_id: options[:device].id)
    Logger.info("Start snapshot uploader")
    send(self(), :init_config)
    {:ok, %{device: options[:device]}}
  end

  @impl true
  def handle_info(:init_config, %{device: device} = state) do
    snapshot_config = device.snapshot_config
    stream_config = device.stream_config

    with false <- is_nil(stream_config.snapshot_uri),
         true <- snapshot_config.enabled,
         %RemoteStorage{} = remote_storage <-
           RemoteStorages.get_by(name: snapshot_config.remote_storage) do
      send(self(), :upload_snapshot)
      {:noreply, Map.put(state, :remote_storage, remote_storage)}
    else
      _ ->
        {:stop, :normal}
    end
  end

  @impl true
  def handle_info(:upload_snapshot, %{device: device, remote_storage: remote_storage} = state) do
    snapshot_config = device.snapshot_config
    utc_now = DateTime.utc_now()

    with {:ok, snapshot} <- Devices.fetch_snapshot(device),
         :ok <- save_snapshot(remote_storage, device.id, utc_now, snapshot) do
      :ok
    end

    Process.send_after(self(), :upload_snapshot, :timer.seconds(snapshot_config.upload_interval))
    {:noreply, state}
  end

  defp save_snapshot(%{type: :s3} = remote_storage, device_id, utc_now, snapshot) do
    S3.save_snapshot(remote_storage, device_id, utc_now, snapshot)
  end

  defp save_snapshot(%{type: :http} = remote_storage, device_id, utc_now, snapshot) do
    HTTP.save_snapshot(remote_storage, device_id, utc_now, snapshot)
  end
end
