defmodule ExNVR.Nerves.Monitoring.UPSTest do
  use ExNVR.DataCase, async: false

  import ExUnit.CaptureLog

  alias ExNVR.Nerves.Monitoring.UPS
  alias ExNVR.Nerves.SystemSettings

  @moduletag :tmp_dir
  @moduletag capture_log: true

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:ex_nvr_fw, :system_settings_path, Path.join(tmp_dir, "settings.json"))
    # make system settings process pick the path
    # in the config above
    Process.exit(Process.whereis(SystemSettings), :kill)
    :ok
  end

  test "Power state" do
    # Power pins (3.3v)
    assert {:ok, ac_power} = Circuits.GPIO.open({"gpiochip0", 0}, :output)
    assert {:ok, bat_power} = Circuits.GPIO.open({"gpiochip0", 4}, :output)

    Circuits.GPIO.write(ac_power, 1)

    pid = start_link_supervised!({UPS, [ac_pin: {"gpiochip0", 1}, battery_pin: {"gpiochip0", 5}]})
    refute UPS.state(false, pid)
    assert %{ac_ok?: true, low_battery?: false} = UPS.state(true, pid)

    SystemSettings.update_ups_settings(%{
      trigger_after: 0,
      ac_failure_action: "stop_recording",
      low_battery_action: "stop_recording"
    })

    # Simulate switch bouncing
    ac_series = [1, 1, 0, 1, 0, 0, 0, 0]
    bat_series = [0, 0, 0, 1, 0, 1, 1, 1]

    logs =
      capture_log(fn ->
        Enum.each(ac_series, &Circuits.GPIO.write(ac_power, &1))
        Process.sleep(to_timeout(millisecond: 1200))
        assert %{ac_ok?: false, low_battery?: false} = UPS.state(false, pid)

        Circuits.GPIO.write(ac_power, 1)
        Process.sleep(to_timeout(millisecond: 1200))
      end)

    assert logs =~ "[UPS] stop recording"
    assert logs =~ "[UPS] start recording"

    assert {:ok, {[event1, event2], _flop}} =
             ExNVR.Events.list_events(%Flop{filters: Flop.Filter.new(type: "power")})

    assert event1.metadata["state"] == 0
    assert event2.metadata["state"] == 1

    logs =
      capture_log(fn ->
        Enum.each(bat_series, &Circuits.GPIO.write(bat_power, &1))
        Process.sleep(to_timeout(millisecond: 1200))
        assert %{ac_ok?: true, low_battery?: true} = UPS.state(false, pid)

        Circuits.GPIO.write(bat_power, 0)
        Process.sleep(to_timeout(millisecond: 1200))
      end)

    assert logs =~ "[UPS] stop recording"
    assert logs =~ "[UPS] start recording"

    assert {:ok, {[event1, event2], _flop}} =
             ExNVR.Events.list_events(%Flop{filters: Flop.Filter.new(type: "low-battery")})

    assert event1.metadata["state"] == 1
    assert event2.metadata["state"] == 0

    assert SystemSettings.get_settings().ups.enabled
  end
end
