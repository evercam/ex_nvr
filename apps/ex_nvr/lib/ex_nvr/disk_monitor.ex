defmodule ExNVR.DiskMonitor do
  use GenServer

  require Logger

  alias ExNVR.Recordings

  @interval_timer :timer.minutes(1)
  @ticks_until_delete 5
  @recordings_count_to_delete 30

  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  @impl true
  def init(options) do
    Logger.metadata(device_id: options[:device].id)
    Logger.debug("Start disk monitor")
    send(self(), :tick)
    {:ok, %{device: options[:device], full_space_ticks: 0}}
  end

  @impl true
  def handle_info(:tick, %{device: device, full_space_ticks: full_space_ticks} = state)
      when device.settings.override_on_full_disk do
    used_space = get_device_disk_usage(device)
    Logger.info("Disk usage #{used_space}")

    state =
      cond do
        used_space >= device.settings.override_on_full_disk_threshold and
            full_space_ticks >= @ticks_until_delete ->
          Logger.info("Deleting old recordings because of hard drive nearly full")
          Recordings.delete_oldest_recordings(device, @recordings_count_to_delete)
          %{state | full_space_ticks: 0}

        used_space >= device.settings.override_on_full_disk_threshold ->
          %{state | full_space_ticks: full_space_ticks + 1}

        true ->
          %{state | full_space_ticks: 0}
      end

    Process.send_after(self(), :tick, @interval_timer)
    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state), do: {:noreply, state}

  defp get_device_disk_usage(device) do
    [{_mountpoint, total, avail, _percentage}] =
      :disksup.get_disk_info(device.settings.storage_address)

    case total do
      0 -> 0
      total -> (1 - avail / total) * 100
    end
  end
end
