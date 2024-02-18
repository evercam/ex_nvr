defmodule ExNVR.RemoteStorages.SnapshotUploader do
  use GenServer, restart: :transient

  require Logger

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
        Logger.info("Stop snapshot uploader")
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info(:upload_snapshot, %{device: device, remote_storage: remote_storage} = state) do
    snapshot_config = device.snapshot_config
    utc_now = DateTime.utc_now()

    with true <- scheduled?(device),
         {:ok, snapshot} <- Devices.fetch_snapshot(device) do
      Store.save_snapshot(remote_storage, device.id, utc_now, snapshot)
    end

    Process.send_after(self(), :upload_snapshot, :timer.seconds(snapshot_config.upload_interval))
    {:noreply, state}
  end

  defp scheduled?(%{timezone: timezone, snapshot_config: %{schedule: schedule}}) do
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
    time_intervals
    |> Enum.map(fn time_interval ->
      [start_time, end_time] = String.split(time_interval, "-")

      %{
        start_time: Time.from_iso8601!(start_time <> ":00"),
        end_time: Time.from_iso8601!(end_time <> ":00")
      }
    end)
    |> Enum.any?(fn time_interval ->
      Time.compare(time_interval.start_time, current_time) in [:lt, :eq] &&
        Time.before?(current_time, time_interval.end_time)
    end)
  end
end
