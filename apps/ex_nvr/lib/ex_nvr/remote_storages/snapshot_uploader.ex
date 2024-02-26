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
    {:ok, %{device: options[:device], schedule: %{}, opts: []}}
  end

  @impl true
  def handle_info(:init_config, %{device: device} = state) do
    snapshot_config = device.snapshot_config
    stream_config = device.stream_config

    with false <- is_nil(stream_config.snapshot_uri),
         true <- snapshot_config.enabled,
         %RemoteStorage{} = remote_storage <-
           RemoteStorages.get_by(name: snapshot_config.remote_storage) do
      schedule = parse_schedule(device)
      opts = build_opts(remote_storage)
      send(self(), :upload_snapshot)
      {:noreply, %{state | schedule: schedule, opts: opts}}
    else
      _ ->
        Logger.info("Stop snapshot uploader")
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info(:upload_snapshot, %{device: device, schedule: schedule, opts: opts} = state) do
    snapshot_config = device.snapshot_config
    utc_now = DateTime.utc_now()

    with true <- scheduled?(device, schedule),
         {:ok, snapshot} <- Devices.fetch_snapshot(device) do
      Store.save_snapshot(device, snapshot, utc_now, opts)
    end

    Process.send_after(self(), :upload_snapshot, :timer.seconds(snapshot_config.upload_interval))
    {:noreply, state}
  end

  defp parse_schedule(device) do
    device.snapshot_config.schedule
    |> Enum.map(fn {day_of_week, day_schedule} ->
      {day_of_week, parse_time_intervals(day_schedule)}
    end)
    |> Map.new()
  end

  defp parse_time_intervals(day_schedule) do
    Enum.map(day_schedule, fn time_interval ->
      [start_time, end_time] = String.split(time_interval, "-")

      %{
        start_time: Time.from_iso8601!(start_time <> ":00"),
        end_time: Time.from_iso8601!(end_time <> ":00")
      }
    end)
  end

  defp build_opts(%{s3_config: s3_config, http_config: http_config} = remote_storage) do
    Map.merge(s3_config, http_config)
    |> Map.from_struct()
    |> Map.put(:url, remote_storage.url)
    |> Map.put(:type, remote_storage.type)
    |> add_auth_type()
    |> parse_url()
    |> Map.to_list()
  end

  defp add_auth_type(%{utype: :s3} = config), do: config

  defp add_auth_type(%{username: username, password: password, token: token} = config) do
    cond do
      not is_nil(token) ->
        Map.put(config, :auth_type, :bearer)

      not is_nil(username) && not is_nil(password) ->
        Map.put(config, :auth_type, :basic)

      true ->
        config
    end
  end

  defp parse_url(%{type: :http} = config), do: config
  defp parse_url(%{url: nil} = config), do: config

  defp parse_url(config) do
    uri = URI.parse(config.url)

    Map.merge(config, %{scheme: uri.scheme, host: uri.host, port: uri.port})
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
        Time.before?(current_time, time_interval.end_time)
    end)
  end
end
