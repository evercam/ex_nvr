defmodule ExNVR.SystemSettingsTest do
  @moduledoc false
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  alias ExNVR.Nerves.SystemSettings

  @default_settings %SystemSettings.State{
    router: %SystemSettings.State.Router{
      username: nil,
      password: nil
    },
    power_schedule: %SystemSettings.State.PowerSchedule{
      schedule: nil,
      timezone: "UTC",
      action: :power_off
    },
    ups: %SystemSettings.State.UPS{
      enabled: false,
      ac_pin: "GPIO23",
      battery_pin: "GPIO16",
      ac_failure_action: :nothing,
      low_battery_action: :stop_recording
    }
  }

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:ex_nvr_fw, :system_settings_path, Path.join(tmp_dir, "settings.json"))
  end

  test "system settings" do
    assert pid = start_link_supervised!({SystemSettings, [name: SystemSettingsTest]})

    assert SystemSettings.get_settings(pid) == @default_settings

    assert {:ok, settings} =
             SystemSettings.update_router_settings(pid, %{
               "username" => "user",
               "password" => "pass"
             })

    assert settings == %SystemSettings.State{
             @default_settings
             | router: %SystemSettings.State.Router{username: "user", password: "pass"}
           }

    assert {:ok, settings} =
             SystemSettings.update_power_schedule_settings(pid, %{
               schedule: %{"1" => ["10:00-15:00"]},
               action: "nothing"
             })

    assert settings == %SystemSettings.State{
             @default_settings
             | router: %SystemSettings.State.Router{username: "user", password: "pass"},
               power_schedule: %SystemSettings.State.PowerSchedule{
                 schedule: %{"1" => ["10:00-15:00"]},
                 action: :nothing,
                 timezone: "UTC"
               }
           }

    assert {:ok, settings} =
             SystemSettings.update_power_schedule_settings(pid, %{timezone: "Africa/Algiers"})

    assert settings.power_schedule ==
             %SystemSettings.State.PowerSchedule{
               schedule: %{"1" => ["10:00-15:00"]},
               action: :nothing,
               timezone: "Africa/Algiers"
             }
  end

  test "ignore wrong settings" do
    assert pid = start_link_supervised!({SystemSettings, [name: SystemStatusTest]})

    assert SystemSettings.get_settings(pid) == @default_settings

    assert {:error, _changeset} =
             SystemSettings.update_router_settings(pid, %{
               "username" => 15,
               "passwor" => "pass"
             })

    assert SystemSettings.get_settings(pid).router == %SystemSettings.State.Router{
             username: nil,
             password: nil
           }
  end
end
