defmodule ExNVR.BifGeneratorServer do
  @moduledoc """
  A process that periodically generates BIF (Base Index Frames) files
  """

  use GenServer

  require Logger

  alias ExNVR.Pipelines.BifGenerator
  alias ExNVR.Utils

  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  @impl true
  def init(options) do
    Process.send_after(self(), :tick, :timer.minutes(1))
    Logger.metadata(device_id: options[:device].id)
    {:ok, %{device: options[:device]}}
  end

  @impl true
  def handle_info(:tick, %{device: device} = state) do
    list_hours(device)
    |> Enum.each(fn start_date ->
      Logger.info("BifGenerator: generate BIF file #{inspect(start_date)}")

      {:ok, _sup_pid, pip_pid} =
        BifGenerator.start(
          device_id: device.id,
          start_date: start_date,
          end_date: DateTime.add(start_date, 1, :hour),
          location: bif_location(device, start_date)
        )

      wait_for_pipeline(pip_pid)
    end)

    Process.send_after(self(), :tick, :timer.minutes(5))
    {:noreply, state}
  end

  def list_hours(device) do
    start_date = from_stored_files(device)

    ExNVR.Recordings.list_runs(device_id: device.id, start_date: start_date)
    |> Enum.flat_map(fn run ->
      Stream.iterate(truncate_to_hour(run.start_date), &DateTime.add(&1, 1, :hour))
      |> Stream.take_while(&(DateTime.compare(&1, run.end_date) != :gt))
      |> Enum.to_list()
    end)
    |> Enum.uniq()
    |> Enum.filter(fn date ->
      DateTime.compare(date, start_date) != :lt and
        DateTime.diff(DateTime.utc_now(), date, :minute) >= 62
    end)
  end

  defp from_stored_files(device) do
    Utils.bif_dir(device.id)
    |> Path.join("*.bif")
    |> Path.wildcard()
    |> Enum.sort(:desc)
    |> List.first()
    |> case do
      nil ->
        DateTime.from_unix!(0)

      file ->
        Path.basename(file, ".bif")
        |> date_from_file_name()
        |> DateTime.add(1, :hour)
    end
  end

  defp date_from_file_name(
         <<year::binary-size(4), month::binary-size(2), day::binary-size(2),
           hour::binary-size(2)>>
       ) do
    {:ok, datetime, _offset} = DateTime.from_iso8601("#{year}-#{month}-#{day}T#{hour}:00:00Z")
    datetime
  end

  defp truncate_to_hour(datetime) do
    date = DateTime.to_date(datetime)
    time = Time.new!(DateTime.to_time(datetime).hour, 0, 0)
    DateTime.new!(date, time)
  end

  defp bif_location(device, start_date) do
    formatted_date = Calendar.strftime(start_date, "%Y%m%d%H.bif")
    Path.join(Utils.bif_dir(device.id), formatted_date)
  end

  defp wait_for_pipeline(pip_pid) do
    if Process.alive?(pip_pid) do
      Process.sleep(100)
      wait_for_pipeline(pip_pid)
    end
  end
end
