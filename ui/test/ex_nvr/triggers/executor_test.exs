defmodule ExNVR.Triggers.ExecutorTest do
  use ExNVR.DataCase

  import ExUnit.CaptureLog
  import ExNVR.DevicesFixtures
  import ExNVR.TriggersFixtures

  alias ExNVR.Events
  alias ExNVR.Triggers.Executor

  @moduletag :tmp_dir

  setup ctx do
    device = camera_device_fixture(ctx.tmp_dir)
    %{device: device}
  end

  describe "evaluate/2 with log_message target" do
    test "logs event with configured level and prefix", %{device: device} do
      full_trigger_fixture(device, %{
        event_type: "temperature_alert",
        target_type: "log_message",
        target_config: %{"level" => "warning", "message_prefix" => "ALERT"}
      })

      {:ok, event} =
        Events.create_event(device, %{
          "type" => "temperature_alert",
          "metadata" => %{"temp" => 42}
        })

      log =
        capture_log([level: :warning], fn ->
          Executor.evaluate(event)
        end)

      assert log =~ "ALERT:"
      assert log =~ "temperature_alert"
    end

    test "does nothing for events without device_id" do
      {:ok, event} = Events.create_event(%{"type" => "standalone_event"})

      assert Executor.evaluate(event) == :ok
    end
  end

  describe "evaluate/2 with device_control target" do
    test "starts recording with action=start", %{device: device} do
      full_trigger_fixture(device, %{
        event_type: "motion_detected",
        target_type: "device_control",
        target_config: %{"action" => "start"}
      })

      {:ok, event} = Events.create_event(device, %{"type" => "motion_detected"})
      test_pid = self()

      mock_updater = fn dev, state ->
        send(test_pid, {:update_state, dev.id, state})
        {:ok, dev}
      end

      Executor.evaluate(event,
        state_updater: mock_updater,
        device_loader: fn _id -> device end
      )

      assert_received {:update_state, _, :recording}
    end

    test "stops recording with action=stop", %{device: device} do
      full_trigger_fixture(device, %{
        event_type: "motion_ended",
        target_type: "device_control",
        target_config: %{"action" => "stop"}
      })

      {:ok, event} = Events.create_event(device, %{"type" => "motion_ended"})
      test_pid = self()

      mock_updater = fn dev, state ->
        send(test_pid, {:update_state, dev.id, state})
        {:ok, dev}
      end

      Executor.evaluate(event,
        state_updater: mock_updater,
        device_loader: fn _id -> device end
      )

      assert_received {:update_state, _, :stopped}
    end

    test "toggles recording with action=toggle", %{device: device} do
      full_trigger_fixture(device, %{
        event_type: "button_press",
        target_type: "device_control",
        target_config: %{"action" => "toggle"}
      })

      {:ok, event} = Events.create_event(device, %{"type" => "button_press"})
      test_pid = self()

      mock_updater = fn dev, state ->
        send(test_pid, {:update_state, dev.id, state})
        {:ok, dev}
      end

      Executor.evaluate(event,
        state_updater: mock_updater,
        device_loader: fn _id -> device end
      )

      assert_received {:update_state, _, :stopped}
    end

    test "logs warning when device not found", %{device: device} do
      full_trigger_fixture(device, %{
        event_type: "motion_detected",
        target_type: "device_control",
        target_config: %{"action" => "start"}
      })

      {:ok, event} = Events.create_event(device, %{"type" => "motion_detected"})

      log =
        capture_log([level: :warning], fn ->
          Executor.evaluate(event, device_loader: fn _id -> nil end)
        end)

      assert log =~ "not found"
    end
  end

  describe "evaluate/2 with no matching triggers" do
    test "does nothing when no triggers match", %{device: device} do
      {:ok, event} = Events.create_event(device, %{"type" => "unmatched_event"})

      assert Executor.evaluate(event) == :ok
    end
  end

  describe "evaluate/2 with disabled targets" do
    test "skips disabled target configs", %{device: device} do
      trigger = trigger_config_fixture()
      source_config_fixture(trigger, %{config: %{"event_type" => "test"}})

      target_config_fixture(trigger, %{
        target_type: "log_message",
        config: %{"level" => "warning", "message_prefix" => "should not appear"},
        enabled: false
      })

      ExNVR.Triggers.set_device_trigger_configs(device.id, [trigger.id])

      {:ok, event} = Events.create_event(device, %{"type" => "test"})

      log =
        capture_log([level: :warning], fn ->
          Executor.evaluate(event)
        end)

      refute log =~ "should not appear"
    end
  end

  describe "evaluate/2 with multiple targets" do
    test "executes all enabled targets for a trigger", %{device: device} do
      trigger = trigger_config_fixture()
      source_config_fixture(trigger, %{config: %{"event_type" => "multi_test"}})

      target_config_fixture(trigger, %{
        target_type: "log_message",
        config: %{"level" => "warning", "message_prefix" => "LOG_TARGET"}
      })

      target_config_fixture(trigger, %{
        target_type: "device_control",
        config: %{"action" => "start"}
      })

      ExNVR.Triggers.set_device_trigger_configs(device.id, [trigger.id])

      {:ok, event} = Events.create_event(device, %{"type" => "multi_test"})
      test_pid = self()

      mock_updater = fn dev, state ->
        send(test_pid, {:update_state, dev.id, state})
        {:ok, dev}
      end

      log =
        capture_log([level: :warning], fn ->
          Executor.evaluate(event,
            state_updater: mock_updater,
            device_loader: fn _id -> device end
          )
        end)

      assert log =~ "LOG_TARGET:"
      assert_received {:update_state, _, :recording}
    end
  end
end
