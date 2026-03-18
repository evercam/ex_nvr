defmodule ExNVR.Triggers.Targets.DeviceControlTest do
  use ExUnit.Case, async: true

  alias ExNVR.Triggers.Targets.DeviceControl

  describe "label/0" do
    test "returns human-readable label" do
      assert DeviceControl.label() == "Device Control"
    end
  end

  describe "config_fields/0" do
    test "returns action field" do
      fields = DeviceControl.config_fields()
      assert length(fields) == 1
      assert %{name: :action, type: :select} = hd(fields)
    end

    test "action has start, stop, toggle options" do
      field = hd(DeviceControl.config_fields())
      values = Enum.map(field.options, &elem(&1, 1))
      assert "start" in values
      assert "stop" in values
      assert "toggle" in values
    end
  end

  describe "validate_config/1" do
    test "accepts start action" do
      assert {:ok, %{"action" => "start"}} =
               DeviceControl.validate_config(%{"action" => "start"})
    end

    test "accepts stop action" do
      assert {:ok, %{"action" => "stop"}} =
               DeviceControl.validate_config(%{"action" => "stop"})
    end

    test "accepts toggle action" do
      assert {:ok, %{"action" => "toggle"}} =
               DeviceControl.validate_config(%{"action" => "toggle"})
    end

    test "accepts atom keys" do
      assert {:ok, %{"action" => "start"}} =
               DeviceControl.validate_config(%{action: "start"})
    end

    test "defaults to start" do
      assert {:ok, %{"action" => "start"}} = DeviceControl.validate_config(%{})
    end

    test "rejects invalid action" do
      assert {:error, [action: _]} =
               DeviceControl.validate_config(%{"action" => "restart"})
    end
  end

  describe "execute/3" do
    test "starts recording with action=start" do
      test_pid = self()
      device = %{id: "dev-1", state: :recording}
      trigger = {:event_created, %{type: "motion", device_id: "dev-1"}}
      config = %{"action" => "start"}

      opts = [
        device_id: "dev-1",
        device_loader: fn _id -> device end,
        state_updater: fn dev, state ->
          send(test_pid, {:update, dev.id, state})
          {:ok, dev}
        end
      ]

      assert :ok = DeviceControl.execute(trigger, config, opts)
      assert_received {:update, "dev-1", :recording}
    end

    test "stops recording with action=stop" do
      test_pid = self()
      device = %{id: "dev-1", state: :recording}
      trigger = {:event_created, %{type: "motion_ended", device_id: "dev-1"}}
      config = %{"action" => "stop"}

      opts = [
        device_id: "dev-1",
        device_loader: fn _id -> device end,
        state_updater: fn dev, state ->
          send(test_pid, {:update, dev.id, state})
          {:ok, dev}
        end
      ]

      assert :ok = DeviceControl.execute(trigger, config, opts)
      assert_received {:update, "dev-1", :stopped}
    end

    test "returns error when device not found" do
      trigger = {:event_created, %{type: "motion", device_id: "missing"}}
      config = %{"action" => "start"}

      opts = [device_id: "missing", device_loader: fn _id -> nil end]

      assert {:error, :device_not_found} = DeviceControl.execute(trigger, config, opts)
    end

    test "returns error when state update fails" do
      device = %{id: "dev-1", state: :recording}
      trigger = {:event_created, %{type: "motion", device_id: "dev-1"}}
      config = %{"action" => "start"}

      opts = [
        device_id: "dev-1",
        device_loader: fn _id -> device end,
        state_updater: fn _dev, _state -> {:error, :some_reason} end
      ]

      assert {:error, :some_reason} = DeviceControl.execute(trigger, config, opts)
    end
  end
end
