defmodule ExNVR.Nerves.RemoteConfigHandler do
  @moduledoc false

  require Logger

  alias ExNVR.Nerves.Monitoring.PowerSchedule
  alias ExNVR.Nerves.{RUT, SystemSettings}

  def handle_message("config", config) do
    Logger.info("[RemoteConfigHandler] handle new incoming config event")

    settings = SystemSettings.get_settings()

    settings = %{
      settings
      | power_schedule: config["power_schedule"],
        schedule_timezone: config["schedule_timezone"],
        schedule_action: config["schedule_action"] || settings.schedule_action,
        router_username: config["router_username"],
        router_password: config["router_password"]
    }

    :ok = SystemSettings.update_settings(settings)

    PowerSchedule.reload()
    RUT.reload()
  end
end
