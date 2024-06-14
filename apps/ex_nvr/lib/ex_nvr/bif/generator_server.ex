defmodule ExNVR.BIF.GeneratorServer do
  @moduledoc """
  A process that periodically generates BIF (Base Index Frames) files
  """

  use GenServer

  require Logger

  alias ExNVR.BIF.Writer
  alias ExNVR.Model.Device

  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  @impl true
  def init(options) do
    Process.send_after(self(), :tick, 0)
    Logger.metadata(device_id: options[:device].id)
    Logger.info("Start BIF generator server")
    {:ok, %{device: options[:device]}}
  end

  @impl true
  def handle_info(:tick, %{device: device} = state) do
    current_hour = DateTime.utc_now() |> DateTime.to_unix()
    current_hour = current_hour - rem(current_hour, 3600)

    Device.bif_thumbnails_dir(device)
    |> Path.join("[0-9]*.jpg")
    |> Path.wildcard()
    |> Enum.group_by(fn path ->
      timestamp = Path.basename(path, ".jpg") |> String.to_integer()
      timestamp - rem(timestamp, 3600)
    end)
    |> Enum.filter(fn {hour, _files} -> hour < current_hour end)
    |> Enum.each(fn {hour, files} ->
      Logger.info(
        "BifGenerator: generate BIF file #{DateTime.from_unix!(hour) |> DateTime.to_iso8601()}"
      )

      files = Enum.sort(files)

      generate_bif!(device, {hour, files})
      copy_first_image_to_thumbnails!(device, {hour, files})
      delete_files!(files)
    end)

    schedule_next_tick()
    {:noreply, state}
  end

  defp generate_bif!(device, {hour, files}) do
    writer = Writer.new(file_location(device, hour))

    files
    |> Enum.reduce(writer, fn file, writer ->
      second_in_hour = Path.basename(file, ".jpg") |> String.to_integer() |> rem(3600)
      image_data = File.read!(file)

      Writer.write!(writer, image_data, second_in_hour)
    end)
    |> Writer.finalize!()
  end

  defp copy_first_image_to_thumbnails!(device, {hour, files}) do
    dest_file = Path.join(Device.thumbnails_dir(device), "#{hour}.jpg")
    File.cp!(List.first(files), dest_file)
  end

  defp delete_files!(files), do: Enum.each(files, &File.rm!/1)

  defp file_location(device, hour) do
    filename = Calendar.strftime(DateTime.from_unix!(hour), "%Y%m%d%H.bif")
    Path.join(Device.bif_dir(device), filename)
  end

  defp schedule_next_tick() do
    seconds_in_hour = DateTime.utc_now() |> DateTime.to_unix() |> rem(3600)
    seconds_to_next_hour = 3600 - seconds_in_hour + 5
    Process.send_after(self(), :tick, :timer.seconds(seconds_to_next_hour))
  end
end
