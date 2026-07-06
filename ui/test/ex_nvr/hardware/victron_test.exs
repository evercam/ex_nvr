defmodule ExNVR.Hardware.VictronTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias ExNVR.Hardware.Victron

  describe "battery_monitor?/1" do
    test "true for known SmartShunt product ids" do
      for pid <- ["0xA389", "0xA38A", "0xA38B"] do
        assert Victron.battery_monitor?(pid)
      end
    end

    test "false for solar chargers and nil" do
      refute Victron.battery_monitor?("0xA053")
      refute Victron.battery_monitor?(nil)
    end
  end

  describe "load_output_state_query/0" do
    test "returns the fixed query command" do
      assert Victron.load_output_state_query() == ":7ABED00B6\n"
    end
  end

  describe "set_load_output_state_command/1" do
    test "encodes value and checksum for :on" do
      # value = 4 -> "04", checksum = 0xB5 - 4 = 0xB1 -> "B1"
      assert Victron.set_load_output_state_command(:on) == ":8ABED0004B1\n"
    end

    test "encodes value and checksum for :off" do
      # value = 0 -> "00", checksum = 0xB5 -> "B5"
      assert Victron.set_load_output_state_command(:off) == ":8ABED0000B5\n"
    end

    test "encodes value and checksum for :aes" do
      # value = 7 -> "07", checksum = 0xB5 - 7 = 0xAE -> "AE"
      assert Victron.set_load_output_state_command(:aes) == ":8ABED0007AE\n"
    end
  end

  describe "parse_load_output_response/1" do
    test "ignores asynchronous messages" do
      assert Victron.parse_load_output_response("A123456789") == :ignore
    end

    test "decodes a successful response into the load output state" do
      # command byte + "ABED" + flags "00" + value "04" (:on) + checksum
      assert Victron.parse_load_output_response("7ABED0004B1") == {:ok, :on}
      assert Victron.parse_load_output_response("7ABED0000B5") == {:ok, :off}
    end

    test "returns invalid_response when flags are non-zero" do
      assert Victron.parse_load_output_response("7ABED0104B1") == {:error, :invalid_response}
    end

    test "returns unexpected_response for a malformed message" do
      assert Victron.parse_load_output_response("garbage") == {:error, :unexpected_response}
    end
  end

  describe "parse/2 text frames" do
    test "parses key/value text frames into the struct" do
      buffer = "PID\t0xA053\r\nV\t25000\r\nI\t1600\r\nSOC\t950\r\n"

      assert {data, [], ""} = Victron.parse(%Victron{}, buffer)
      assert data.pid == "0xA053"
      assert data.v == 25_000
      assert data.i == 1_600
      assert data.soc == 950
    end

    test "keys are case-insensitive" do
      assert {data, [], ""} = Victron.parse(%Victron{}, "v\t42\r\n")
      assert data.v == 42
    end

    test "maps the operation state (CS)" do
      assert {%{cs: :bulk}, [], ""} = Victron.parse(%Victron{}, "CS\t3\r\n")
      assert {%{cs: :float}, [], ""} = Victron.parse(%Victron{}, "CS\t5\r\n")
      assert {%{cs: :unknown}, [], ""} = Victron.parse(%Victron{}, "CS\t99\r\n")
    end

    test "decodes the off reason from hex" do
      assert {%{off_reason: 5}, [], ""} = Victron.parse(%Victron{}, "OR\t0x00000005\r\n")
    end

    test "decodes alarm/load into atoms" do
      assert {data, [], ""} = Victron.parse(%Victron{}, "LOAD\tON\r\nALARM\tOFF\r\n")
      assert data.load == :on
      assert data.alarm == :off
    end

    test "decodes relay into the relay_state field" do
      assert {data, [], ""} = Victron.parse(%Victron{}, "RELAY\tON\r\n")
      assert data.relay_state == :on
    end

    test "decodes alarm reasons from the bitmask" do
      # bit 0 (low_voltage) + bit 2 (low_soc) = 5
      assert {data, [], ""} = Victron.parse(%Victron{}, "AR\t5\r\n")
      assert Enum.sort(data.alarm_reasons) == Enum.sort([:low_voltage, :low_soc])
    end

    test "ignores unknown keys" do
      assert {%Victron{}, [], ""} = Victron.parse(%Victron{}, "UNKNOWN\tvalue\r\n")
    end
  end

  describe "parse/2 buffering" do
    test "returns the trailing incomplete frame as remaining buffer" do
      assert {data, [], "I\t16"} = Victron.parse(%Victron{}, "V\t25000\r\nI\t16")
      assert data.v == 25_000
    end

    test "resuming with the remaining buffer yields the full value" do
      {data, [], rest} = Victron.parse(%Victron{}, "V\t25000\r\nI\t16")
      assert {data, [], ""} = Victron.parse(data, rest <> "00\r\n")
      assert data.i == 1_600
    end
  end

  describe "parse/2 hex frames" do
    test "collects a hex frame embedded in the stream, buffering trailing text" do
      buffer = "V\t25000\r\n:7ABED0004B1\nI\t1600\r\n"

      # the hex frame's terminator consumes the line delimiter, so the text that
      # follows it stays buffered until the next \r\n arrives.
      assert {data, ["7ABED0004B1"], "I\t1600"} = Victron.parse(%Victron{}, buffer)
      assert data.v == 25_000
    end

    test "collects multiple consecutive hex frames in order" do
      buffer = ":7ABED0004B1\n:7ABED0000B5\nV\t1\r\n"

      assert {_data, ["7ABED0004B1", "7ABED0000B5"], "V\t1"} =
               Victron.parse(%Victron{}, buffer)
    end
  end
end
