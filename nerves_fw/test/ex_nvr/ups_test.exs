defmodule ExNVR.Nerves.Monitoring.UPSTest do
  use ExNVR.DataCase, async: false

  import ExUnit.CaptureLog
  import Mimic

  alias ExNVR.Nerves.Monitoring.UPS
  alias ExNVR.Nerves.SystemSettings

  @moduletag :tmp_dir
  @moduletag capture_log: true

  setup :set_mimic_global
  setup :verify_on_exit!

  setup_all do
    Mimic.copy(ExNVR.Nerves.DiskMounter)
  end

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:ex_nvr_fw, :system_settings_path, Path.join(tmp_dir, "settings.json"))
    # make system settings process pick the path
    # in the config above
    Process.exit(Process.whereis(SystemSettings), :kill)

    expect(ExNVR.Nerves.DiskMounter, :mount, 3, fn -> :ok end)

    :ok
  end

  test "Power state" do
    assert {:ok, _settings} =
             SystemSettings.update_ups_settings(%{
               enabled: true,
               trigger_after: 0,
               ac_failure_action: "stop_recording",
               low_battery_action: "nothing",
               ac_pin: "pair_0_1",
               battery_pin: "pair_2_1"
             })

    # Power pins (3.3v)
    assert {:ok, ac_power} = Circuits.GPIO.open("pair_0_0", :output)
    assert {:ok, bat_power} = Circuits.GPIO.open("pair_2_0", :output)

    Circuits.GPIO.write(ac_power, 1)

    pid = start_link_supervised!({UPS, []})
    assert %{ac_ok: true, low_battery: false} = UPS.state(pid)

    # Simulate switch bouncing
    ac_series = [1, 1, 0, 1, 0, 0, 0, 0]
    bat_series = [0, 0, 0, 1, 0, 1, 1, 1]

    logs =
      capture_log(fn ->
        Enum.each(ac_series, &Circuits.GPIO.write(ac_power, &1))
        Process.sleep(to_timeout(millisecond: 1200))
        assert %{ac_ok: false, low_battery: false} = UPS.state(pid)

        Circuits.GPIO.write(ac_power, 1)
        Process.sleep(to_timeout(millisecond: 1200))
        assert %{ac_ok: true, low_battery: false} = UPS.state(pid)
      end)

    assert logs =~ "[UPS] stop recording"
    assert logs =~ "[UPS] start recording"

    assert {:ok, {[event1, event2], _flop}} =
             ExNVR.Events.list_events(%Flop{filters: Flop.Filter.new(type: "power")})

    assert event1.metadata["state"] == 0
    assert event2.metadata["state"] == 1

    Enum.each(bat_series, &Circuits.GPIO.write(bat_power, &1))
    Process.sleep(to_timeout(millisecond: 1200))
    assert %{ac_ok: true, low_battery: true} = UPS.state(pid)

    Circuits.GPIO.write(bat_power, 0)
    Process.sleep(to_timeout(millisecond: 1200))

    assert {:ok, {[event1, event2], _flop}} =
             ExNVR.Events.list_events(%Flop{filters: Flop.Filter.new(type: "low-battery")})

    assert event1.metadata["state"] == 1
    assert event2.metadata["state"] == 0

    assert {:ok, _settings} = SystemSettings.update_ups_settings(%{enabled: false})
    refute UPS.state(pid)
  end
end
