defmodule ExNVR.Devices.LPREventsPuller do
  use GenServer

  require Logger

  alias ExNVR.Devices.CameraClient
  alias ExNVR.Events
  alias ExNVR.Model.Device

  @pulling_interval :timer.seconds(10)

  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  @impl true
  def init(options) do
    Logger.metadata(device_id: options[:device].id)
    Logger.info("Start LPR event puller")
    device = options[:device]

    if Device.base_url(device) do
      send(self(), :pull_events)
      {:ok, %{device: options[:device], last_event_timestamp: nil}}
    else
      Logger.info("Stop LPR event puller")
      {:stop, :normal}
    end
  end

  @impl true
  def handle_info(:pull_events, state) do
    %{device: device, last_event_timestamp: last_event_timestamp} = state
    Process.send_after(self(), :pull_events, @pulling_interval)

    with {:ok, records, plates} <- CameraClient.fetch_lpr_event(device, last_event_timestamp),
         :ok <- save_events(device, records, plates) do
      last_event_timestamp =
        records
        |> Enum.map(& &1.capture_time)
        |> Enum.max_by(& &1, DateTime, fn -> last_event_timestamp end)

      {:noreply, %{state | last_event_timestamp: last_event_timestamp}}
    else
      error ->
        Logger.error("Error while pulling LPR events : #{inspect(error)}")
        {:noreply, state}
    end
  end

  defp save_events(device, records, plates) do
    Enum.zip(records, plates)
    |> Enum.each(fn {record, plate} -> Events.create_lpr_event(device, record, plate) end)
  end
end
