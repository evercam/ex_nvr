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
      ac_pin: "GPIO27",
      battery_pin: "GPIO22",
      ac_failure_action: :stop_recording,
      low_battery_action: :nothing
    },
    auto_reboot: %SystemSettings.State.AutoReboot{
      interval: nil,
      reboot_at: nil,
      timezone: "UTC"
    }
  }

  setup %{tmp_dir: tmp_dir} do
    start_supervised!({SystemSettings, [path: Path.join(tmp_dir, "settings.json")]})
    :ok
  end

  test "system settings" do
    assert SystemSettings.get_settings() == @default_settings

    assert {:ok, settings} =
             SystemSettings.update_router_settings(%{
               "username" => "user",
               "password" => "pass"
             })

    assert settings == %SystemSettings.State{
             @default_settings
             | router: %SystemSettings.State.Router{username: "user", password: "pass"}
           }

    assert {:ok, settings} =
             SystemSettings.update_power_schedule_settings(%{
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
             SystemSettings.update_power_schedule_settings(%{timezone: "Africa/Algiers"})

    assert settings.power_schedule ==
             %SystemSettings.State.PowerSchedule{
               schedule: %{"1" => ["10:00-15:00"]},
               action: :nothing,
               timezone: "Africa/Algiers"
             }

    assert {:ok, settings} =
             SystemSettings.update(%{"kit_serial" => "my_kit", "configured" => "true"})

    assert settings.kit_serial == "my_kit"
    assert settings.configured
  end

  test "ignore wrong settings" do
    assert SystemSettings.get_settings() == @default_settings

    assert {:error, _changeset} =
             SystemSettings.update_router_settings(%{
               "username" => 15,
               "passwor" => "pass"
             })

    assert SystemSettings.get_settings().router == %SystemSettings.State.Router{
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

  describe "auto reboot settings" do
    test "are stored and reloaded from disk", %{tmp_dir: tmp_dir} do
      assert {:ok, settings} =
               SystemSettings.update_auto_reboot_settings(%{
                 "interval" => 12,
                 "reboot_at" => "2026-07-30T03:00:00",
                 "timezone" => "Africa/Algiers"
               })

      assert settings.auto_reboot == %SystemSettings.State.AutoReboot{
               interval: 12,
               reboot_at: ~N[2026-07-30 03:00:00],
               timezone: "Africa/Algiers"
             }

      # The json round trip must be lossless, `do_update_settings/2` relies on
      # struct equality to decide whether to broadcast an update.
      stop_supervised!(SystemSettings)
      start_supervised!({SystemSettings, [path: Path.join(tmp_dir, "settings.json")]})

      assert SystemSettings.get_settings().auto_reboot == settings.auto_reboot
    end

    test "ignore the offset of the anchor" do
      assert {:ok, settings} =
               SystemSettings.update_auto_reboot_settings(%{
                 "interval" => 24,
                 "reboot_at" => "2026-07-30T03:00:00Z"
               })

      assert settings.auto_reboot.reboot_at == ~N[2026-07-30 03:00:00]
    end

    test "are disabled by a nil interval" do
      assert {:ok, _settings} =
               SystemSettings.update_auto_reboot_settings(%{
                 interval: 24,
                 reboot_at: ~N[2026-07-30 03:00:00]
               })

      assert {:ok, settings} = SystemSettings.update_auto_reboot_settings(%{interval: nil})
      assert settings.auto_reboot.interval == nil
      assert settings.auto_reboot.reboot_at == ~N[2026-07-30 03:00:00]
    end

    test "are left untouched by an empty update" do
      assert {:ok, settings} =
               SystemSettings.update_auto_reboot_settings(%{
                 interval: 6,
                 reboot_at: ~N[2026-07-30 03:00:00]
               })

      assert {:ok, ^settings} = SystemSettings.update_auto_reboot_settings(%{})
    end

    test "reject an interval outside the predefined list" do
      assert {:error, changeset} = SystemSettings.update_auto_reboot_settings(%{interval: 8})
      assert %{auto_reboot: %{interval: ["is invalid"]}} = errors_on(changeset)
    end

    test "reject a missing anchor when an interval is set" do
      assert {:error, changeset} = SystemSettings.update_auto_reboot_settings(%{interval: 24})
      assert %{auto_reboot: %{reboot_at: ["can't be blank"]}} = errors_on(changeset)
    end

    test "reject an unknown timezone" do
      assert {:error, changeset} =
               SystemSettings.update_auto_reboot_settings(%{timezone: "Mars/Olympus"})

      assert %{auto_reboot: %{timezone: ["is invalid"]}} = errors_on(changeset)
    end

    # The settings form sends the values below verbatim, these tests are the
    # contract the auto reboot card relies on.
    test "are disabled by the empty interval sent by a select input" do
      assert {:ok, _settings} =
               SystemSettings.update_auto_reboot_settings(%{
                 "interval" => "24",
                 "reboot_at" => "2026-07-30T03:00",
                 "timezone" => "UTC"
               })

      assert {:ok, settings} =
               SystemSettings.update_auto_reboot_settings(%{
                 "interval" => "",
                 "reboot_at" => "2026-07-30T03:00",
                 "timezone" => "UTC"
               })

      assert settings.auto_reboot.interval == nil
      assert settings.auto_reboot.reboot_at == ~N[2026-07-30 03:00:00]
    end

    test "accept the minute precision anchor sent by a datetime-local input" do
      assert {:ok, settings} =
               SystemSettings.update_auto_reboot_settings(%{
                 "interval" => "6",
                 "reboot_at" => "2026-07-30T03:00"
               })

      assert settings.auto_reboot.reboot_at == ~N[2026-07-30 03:00:00]
    end

    test "reject a cleared anchor when an interval is set" do
      assert {:error, changeset} =
               SystemSettings.update_auto_reboot_settings(%{
                 "interval" => "12",
                 "reboot_at" => ""
               })

      assert %{auto_reboot: %{reboot_at: ["can't be blank"]}} = errors_on(changeset)
    end

    test "accept a cleared anchor when no interval is set" do
      assert {:ok, settings} =
               SystemSettings.update_auto_reboot_settings(%{
                 "interval" => "",
                 "reboot_at" => ""
               })

      assert settings.auto_reboot.interval == nil
      assert settings.auto_reboot.reboot_at == nil
    end

    test "fall back to the default timezone when it's empty" do
      assert {:ok, _settings} =
               SystemSettings.update_auto_reboot_settings(%{timezone: "Africa/Algiers"})

      assert {:ok, settings} = SystemSettings.update_auto_reboot_settings(%{"timezone" => ""})
      assert settings.auto_reboot.timezone == "UTC"
    end

    test "reject a nil timezone" do
      assert {:error, changeset} =
               SystemSettings.update_auto_reboot_settings(%{timezone: nil})

      assert %{auto_reboot: %{timezone: ["can't be blank"]}} = errors_on(changeset)
    end
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
