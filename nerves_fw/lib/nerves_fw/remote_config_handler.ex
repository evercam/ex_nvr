defmodule ExNVR.Nerves.RemoteConfigHandler do
  @moduledoc false

  require Logger

  alias ExNVR.Nerves.Monitoring.PowerSchedule
  alias ExNVR.Nerves.{RUT, SystemSettings}

  def handle_message("config", config) do
    Logger.info("[RemoteConfigHandler] handle new incoming config event")

    settings = SystemSettings.get_settings()

    new_settings = %{
      settings
      | power_schedule: config["power_schedule"],
        schedule_timezone: config["schedule_timezone"],
        schedule_action: config["schedule_action"] || settings.schedule_action,
        router_username: config["router_username"],
        router_password: config["router_password"]
    }

    :ok = SystemSettings.update_settings(new_settings)
    :ok = PowerSchedule.reload()
    :ok = RUT.reload()

    if settings.power_schedule != new_settings.power_schedule do
      Logger.info("[RemoteConfigHandler] Updating router schedule")
      update_router_schedule(new_settings.power_schedule)
    end
  end

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
