defmodule ExNVR.Devices.SnapshotUploader do
  use GenServer, restart: :transient

  require Logger

  alias ExNVR.Model.Device
  alias ExNVR.RemoteStorage
  alias ExNVR.{Devices, RemoteStorages}
  alias ExNVR.RemoteStorages.Store

  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  @impl true
  def init(options) do
    Logger.metadata(device_id: options[:device].id)
    Logger.info("Start snapshot uploader")
    send(self(), :init_config)
    {:ok, %{device: options[:device], remote_storage: nil, snapshot_config: %{}, opts: []}}
  end

  @impl true
  def handle_info(:init_config, %{device: device} = state) do
    snapshot_config = Device.snapshot_config(device)
    stream_config = device.stream_config

    with false <- is_nil(stream_config.snapshot_uri),
         true <- snapshot_config.enabled,
         %RemoteStorage{} = remote_storage <-
           RemoteStorages.get_by(name: snapshot_config.remote_storage) do
      timeout = min(snapshot_config.upload_interval, 30)
      opts = RemoteStorage.build_opts(remote_storage) ++ [timeout: timeout]

      send(self(), :upload_snapshot)

      {:noreply,
       %{state | remote_storage: remote_storage, snapshot_config: snapshot_config, opts: opts}}
    else
      _ ->
        Logger.info("Stop snapshot uploader")
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info(
        :upload_snapshot,
        %{
          device: device,
          remote_storage: remote_storage,
          snapshot_config: snapshot_config,
          opts: opts
        } = state
      ) do
    utc_now = DateTime.utc_now()
    Process.send_after(self(), :upload_snapshot, :timer.seconds(snapshot_config.upload_interval))

    with true <- scheduled?(device, snapshot_config.schedule) do
      fetch_and_upload_snapshot(remote_storage, device, utc_now, opts)
    end

    {:noreply, state}
  end

  defp scheduled?(%{timezone: timezone}, schedule) do
    now = DateTime.now!(timezone)
    day_of_week = DateTime.to_date(now) |> Date.day_of_week() |> Integer.to_string()

    case Map.get(schedule, day_of_week) do
      [] ->
        false

      time_intervals ->
        scheduled_today?(time_intervals, DateTime.to_time(now))
    end
  end

  defp scheduled_today?(time_intervals, current_time) do
    Enum.any?(time_intervals, fn time_interval ->
      Time.compare(time_interval.start_time, current_time) in [:lt, :eq] &&
        Time.compare(current_time, time_interval.end_time) in [:lt, :eq]
    end)
  end

  defp fetch_and_upload_snapshot(remote_storage, device, utc_now, opts) do
    Task.Supervisor.async_nolink(ExNVR.TaskSupervisor, fn ->
      with {:ok, snapshot} <- Devices.fetch_snapshot(device) do
        Store.save_snapshot(remote_storage, device, snapshot, utc_now, opts)
      end
    end)
    |> then(&(Task.yield(&1, :timer.seconds(opts[:timeout])) || Task.shutdown(&1)))
  end
end
