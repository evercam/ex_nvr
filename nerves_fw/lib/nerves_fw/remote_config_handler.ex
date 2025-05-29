defmodule ExNVR.Nerves.RemoteConfigHandler do
  @moduledoc false

  require Logger

  alias ExNVR.Nerves.{RUT, SystemSettings}

  def handle_message("config", config) do
    Logger.info("[RemoteConfigHandler] handle new incoming config event")

    settings = SystemSettings.get_settings()

    with {:ok, _new_settings} <- SystemSettings.update_router_settings(config["router"] || %{}),
         {:ok, new_settings} <-
           SystemSettings.update_power_schedule_settings(config["power_schedule"] || %{}) do
      if power_schedule_updated?(settings.power_schedule, new_settings.power_schedule) do
        Logger.info("[RemoteConfigHandler] Updating router schedule")
        update_router_schedule(new_settings.power_schedule.schedule)
      end
    else
      {:error, reason} ->
        Logger.error(
          "[RemoteConfigHandler] Failed to update router or power schedule settings: #{inspect(reason)}"
        )
    end
  end

  defp power_schedule_updated?(%{schedule: s}, %{schedule: s}), do: false
  defp power_schedule_updated?(_, _), do: true

  defp update_router_schedule(schedule) do
    schedule = schedule && ExNVR.Model.Schedule.parse!(schedule)
    schedule = add_one_minute(schedule)

    with {:error, reason} <- RUT.set_scheduler(schedule) do
      Logger.error("Failed to set router schedule: #{inspect(reason)}")
      Sentry.capture_message("Failed to set router schedule", extra: %{reason: reason})
    end
  end

  defp add_one_minute(nil), do: nil

  defp add_one_minute(schedule) do
    Map.new(schedule, fn {day, time_intervals} ->
      intervals =
        Enum.map(time_intervals, fn
          %{end_time: ~T(23:59:59)} = interval ->
            interval

          %{end_time: _} = interval ->
            %{interval | end_time: Time.add(interval.end_time, 1, :minute)}
        end)

      {day, intervals}
    end)
  end
end
