defmodule ExNVR.DiskMonitor do
  use GenServer

  require Logger

  alias ExNVR.Recordings
  alias ExNVR.Model.Device

  @interval_timer :timer.minutes(1)
  @wait_until_remove_timer :timer.minutes(5)
  @recordings_count_to_delete 30

  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  @impl true
  def init(options) do
    Logger.metadata(device_id: options[:device].id)
    Logger.info("Start disk monitor")
    send(self(), :tick)
    {:ok, %{device: options[:device]}}
  end

  @impl true
  def handle_info(:tick, %{device: device} = state) do
    with true <- device.settings.override_on_full_disk,
         {:ok, percentage} <- get_device_disk_usage(device),
         true <- percentage >= device.settings.override_on_full_disk_threshold do
      send(self(), :overflow)
    else
      _ -> state = Map.put(state, :timer, 0)
    end

    Process.send_after(self(), :tick, @interval_timer)
    {:noreply, state}
  end

  @impl true
  def handle_info(:overflow, %{device: device, timer: timer} = state) do
    if timer >= @wait_until_remove_timer do
      # delete recordings
      IO.inspect("Deleting old recordings because of hard drive nearly full")
      Recordings.delete_oldest_recordings(device, @recordings_count_to_delete)
      {:noreply, Map.put(state, :timer, 0)}
    else
      {:noreply, Map.put(state, :timer, timer + @interval_timer)}
    end
  end

  @impl true
  def handle_info(:overflow, state) do
    {:noreply, Map.put(state, :timer, 0)}
  end

  defp get_device_disk_usage(device) do
    :disksup.get_disk_data()
    |> Enum.find_value(fn {mountpoint, _total_space, percentage} ->
      if to_string(mountpoint) == device.settings.storage_address do
        {:ok, percentage}
      end
    end)
  end
end
