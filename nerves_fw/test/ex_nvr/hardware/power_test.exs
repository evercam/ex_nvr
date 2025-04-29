defmodule ExNVR.Nerves.Hardware.PowerTest do
  use ExNVR.DataCase, async: false

  alias ExNVR.Nerves.Hardware.Power

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:ex_nvr_fw, :system_settings_path, Path.join(tmp_dir, "settings.json"))
  end

  test "Power state" do
    # Power pins (3.3v)
    assert {:ok, ac_power} = Circuits.GPIO.open({"gpiochip0", 0}, :output)
    assert {:ok, bat_power} = Circuits.GPIO.open({"gpiochip0", 4}, :output)

    Circuits.GPIO.write(ac_power, 1)

    assert {:ok, pid} = Power.start_link(ac_pin: {"gpiochip0", 1}, battery_pin: {"gpiochip0", 5})
    refute Power.state(false, pid)
    assert %{ac_ok?: true, low_battery?: false} = Power.state(true, pid)

    # Simulate switch bouncing
    ac_series = [1, 1, 0, 1, 0, 0, 0, 0]
    bat_series = [0, 0, 0, 1, 0, 1, 1, 1]

    Enum.each(ac_series, &Circuits.GPIO.write(ac_power, &1))
    Enum.each(bat_series, &Circuits.GPIO.write(bat_power, &1))

    Process.sleep(to_timeout(second: 2))

    assert %{ac_ok?: false, low_battery?: true} = Power.state(false, pid)
    assert ExNVR.Nerves.SystemSettings.get_settings().monitor_power

    assert {:ok, {[event], _flop}} =
             ExNVR.Events.list_events(%Flop{filters: Flop.Filter.new(type: "power")})

    assert %{"state" => 0} = event.metadata

    assert {:ok, {[event], _flop}} =
             ExNVR.Events.list_events(%Flop{filters: Flop.Filter.new(type: "low-battery")})

    assert %{"state" => 1} = event.metadata
  end
end
