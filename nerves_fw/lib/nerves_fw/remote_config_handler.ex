defmodule ExNVR.Nerves.RemoteConfigHandler do
  @moduledoc false

  require Logger

  alias ExNVR.{Hardware, Model}
  alias ExNVR.Nerves.{Application, RUT, SystemSettings}
  alias ExNVR.Nerves.Giraffe.Init

  def handle_message("config", config) do
    Logger.info("[RemoteConfigHandler] handle new incoming config event")
    settings = SystemSettings.get_settings()
    do_handle_message(settings.configured, settings, config)
  end

  defp do_handle_message(false, _settings, _config), do: :ok

  defp do_handle_message(_configured, settings, config) do
    params = %{
      router: config["router"] || %{},
      power_schedule: config["power_schedule"] || %{},
      power_type: config["power_type"] || "",
    }

    case SystemSettings.update(params) do
      {:ok, new_settings} ->
        if power_schedule_updated?(settings.power_schedule, new_settings.power_schedule) do
          Logger.info("[RemoteConfigHandler] Updating router schedule")
          update_router_schedule(new_settings.power_schedule.schedule)
        end

        if settings.power_type != new_settings.power_type do
          handle_power_type_update(new_settings.power_type)
        end

      {:error, reason} ->
        Logger.error(
          "[RemoteConfigHandler] Failed to update router or power schedule settings: #{inspect(reason)}"
        )
    end
  end

  defp power_schedule_updated?(%{schedule: s}, %{schedule: s}), do: false
  defp power_schedule_updated?(_, _), do: true

  defp update_router_schedule(schedule) do
    schedule = schedule && Model.Schedule.parse!(schedule)
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

  defp handle_power_type_update(power_type) do
    # Enable/disable victron data gathering
    if power_type in [:solar, :generator],
      do: Hardware.SerialPortChecker.enable(),
      else: Hardware.SerialPortChecker.disable()

    # Enable/disable ups for giraffe
    if Application.target() == :giraffe do
      Init.set_ups(power_type)
    end
  end
end
