defmodule ExNVR.Nerves.Giraffe.DoorSensorTest do
  use ExNVR.DataCase, async: false

  import ExUnit.CaptureLog

  alias ExNVR.Nerves.Giraffe.DoorSensor

  @moduletag capture_log: true

  test "monitors door state and stores events on change" do
    # Door pin (3.3v)
    assert {:ok, door_power} = Circuits.GPIO.open("pair_1_0", :output)
    Circuits.GPIO.write(door_power, 0)

    pid = start_link_supervised!({DoorSensor, [pin: "pair_1_1"]})
    assert DoorSensor.state(pid) == :closed

    capture_log(fn ->
      Circuits.GPIO.write(door_power, 1)
      Process.sleep(to_timeout(millisecond: 1200))
      assert DoorSensor.state(pid) == :open

      Circuits.GPIO.write(door_power, 0)
      Process.sleep(to_timeout(millisecond: 1200))
      assert DoorSensor.state(pid) == :closed
    end)

    assert {:ok, {[event1, event2], _flop}} =
             ExNVR.Events.list_events(%Flop{filters: Flop.Filter.new(type: "door")})

    assert event1.metadata["state"] == "open"
    assert event2.metadata["state"] == "closed"
  end
end
