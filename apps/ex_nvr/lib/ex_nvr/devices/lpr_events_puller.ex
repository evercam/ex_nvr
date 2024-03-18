defmodule ExNVR.Devices.LprEventsPuller do
  use GenServer

  require Logger

  alias ExNVR.Devices.Client
  alias ExNVR.Events

  @pulling_interval 10

  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  @impl true
  def init(options) do
    Logger.metadata(device_id: options[:device].id)
    Logger.info("Start lvr events puller")
    send(self(), :pull_events)
    {:ok, %{device: options[:device], last_event_timestamp: nil}}
  end

  @impl true
  def handle_info(
        :pull_events,
        %{
          device: device,
          last_event_timestamp: last_event_timestamp
        } = state
      ) do
    Process.send_after(self(), :pull_events, :timer.seconds(@pulling_interval))

    with {:ok, records, plates} <- Client.fetch_anpr(device, last_event_timestamp),
         :ok <- save_events(device, records, plates) do
      last_event_timestamp =
        records
        |> Enum.map(&DateTime.shift_zone!(&1.capture_time, device.timezone))
        |> Enum.max(&>=/2, fn -> nil end)
        |> Kernel.||(last_event_timestamp)

      {:noreply, %{state | last_event_timestamp: last_event_timestamp}}
    else
      error ->
        Logger.info("Error while pulling lpr events : #{inspect(error)}")
        {:noreply, state}
    end
  end

  defp save_events(device, records, plates) do
    Enum.zip(records, plates)
    |> Enum.each(fn {record, plate} -> Events.create_lpr_event(device, record, plate) end)
  end
end
