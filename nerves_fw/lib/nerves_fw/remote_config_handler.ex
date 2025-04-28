defmodule ExNVR.Nerves.RemoteConfigHandler do
  @moduledoc false

  require Logger

  alias ExNVR.Nerves.Monitoring.PowerSchedule
  alias ExNVR.Nerves.SystemSettings

  def handle_message("config", config) do
    Logger.info("[RemoteConfigHandler] handle new incoming config event")

    SystemSettings.update_setting(:power_schedule, config["power_schedule"])
    SystemSettings.update_setting(:schedule_timezone, config["schedule_timezone"])

    if action = config["schedule_action"] do
      SystemSettings.update_setting(:schedule_action, config["schedule_action"])
    end

    PowerSchedule.reload()
  end
end
