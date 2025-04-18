defmodule ExNVR.Nerves.Monitoring.PowerTest do
  use ExUnit.Case, async: true

  alias ExNVR.Nerves.Monitoring.Power

  test "Power state" do
    # Power pins (3.3v)
    assert {:ok, ac_power} = Circuits.GPIO.open({"gpiochip0", 0}, :output)
    assert {:ok, bat_power} = Circuits.GPIO.open({"gpiochip0", 4}, :output)

    Circuits.GPIO.write(ac_power, 1)
    Circuits.GPIO.write(bat_power, 0)

    assert {:ok, pid} = Power.start_link(ac_pin: {"gpiochip0", 1}, battery_pin: {"gpiochip0", 5})
    assert %{ac_ok?: 1, low_battery?: 0} = Power.state(pid)

    # Simulate switch bouncing
    ac_series = [1, 1, 0, 1, 0, 0, 0, 0]
    bat_series = [0, 0, 0, 1, 0, 1, 1, 1]

    Enum.each(ac_series, &Circuits.GPIO.write(ac_power, &1))
    Enum.each(bat_series, &Circuits.GPIO.write(bat_power, &1))

    Process.sleep(to_timeout(second: 2))

    assert %{ac_ok?: 0, low_battery?: 1} = Power.state(pid)
    assert {:ok, {[event], _flop}} = ExNVR.Events.list_events(%{type: "power"})
    assert %{"state" => 0} = event.metadata

    assert {:ok, {[event], _flop}} = ExNVR.Events.list_events(%{type: "low-battery"})
    assert %{"state" => 1} = event.metadata
  end
end
