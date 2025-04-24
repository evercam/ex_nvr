defmodule ExNVR.SystemSettingsTest do
  @moduledoc false
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  alias ExNVR.Nerves.SystemSettings

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:ex_nvr_fw, :system_settings_path, Path.join(tmp_dir, "settings.json"))
  end

  test "system settings" do
    assert SystemSettings.get_settings() == %SystemSettings{
             power_schedule: nil,
             schedule_timezone: "UTC",
             schedule_action: "poweroff",
             monitor_power: false
           }

    assert :ok = SystemSettings.update_setting(:power_schedule, %{"1" => ["10:00-15:00"]})
    assert :ok = SystemSettings.update_setting(:monitor_power, true)

    assert SystemSettings.get_settings() == %SystemSettings{
             power_schedule: %{"1" => ["10:00-15:00"]},
             schedule_timezone: "UTC",
             schedule_action: "poweroff",
             monitor_power: true
           }
  end
end
