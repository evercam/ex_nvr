defmodule ExNVR.Devices.LPREventPuller do
  use GenServer

  require Logger

  alias ExNVR.{Devices, Events}

  @pulling_interval :timer.seconds(10)

  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  @impl true
  def init(device: device) do
    Logger.metadata(device_id: device.id)
    Logger.info("Start LPR event puller")

    send(self(), :pull_events)
    {:ok, %{device: device, last_event_timestamp: Events.last_lpr_event_timestamp(device)}}
  end

  @impl true
  def handle_info(:pull_events, state) do
    %{device: device, last_event_timestamp: last_event_timestamp} = state
    Process.send_after(self(), :pull_events, @pulling_interval)

    with {:ok, records, plates} <- Devices.fetch_lpr_event(device, last_event_timestamp),
         stored_events <- save_events(device, records, plates) do
      Logger.info("LPR: stored #{length(stored_events)} events")

      last_event_timestamp =
        stored_events
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
    records
    |> Enum.zip(plates)
    |> Enum.map(fn {record, plate} ->
      case Events.create_lpr_event(device, record, plate) do
        {:ok, event} ->
          event

        {:error, reason} ->
          Logger.error("""
          Could not store lpr event
          due to: #{inspect(reason)}
          """)

          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    # ignore already stored events (id is null)
    |> Enum.reject(&is_nil(&1.id))
  end
end
