defmodule ExNVR.SystemSettingsTest do
  @moduledoc false
  use ExNVR.DataCase, async: true

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

  test "ups: ac and battery pins should not be the same" do
    assert {:error, changeset} =
             SystemSettings.update_ups_settings(%{ac_pin: "GPIO10", battery_pin: "GPIO10"})

    assert %{ups: %{battery_pin: ["AC Pin and Battery Pin should not be the same"]}} =
             errors_on(changeset)
  end

  test "ups: ac and battery actions should not be both 'stop_recording'" do
    assert {:error, changeset} =
             SystemSettings.update_ups_settings(%{
               ac_failure_action: "stop_recording",
               low_battery_action: "stop_recording"
             })

    assert %{ups: %{low_battery_action: ["Both actions cannot be 'stop_recording'"]}} =
             errors_on(changeset)
  end
end
