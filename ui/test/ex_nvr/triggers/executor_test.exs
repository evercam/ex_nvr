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

  describe "evaluate/2 with start_recording target" do
    test "calls pipeline start_recording", %{device: device} do
      full_trigger_fixture(device, %{
        event_type: "motion_detected",
        target_type: "start_recording"
      })

      {:ok, event} = Events.create_event(device, %{"type" => "motion_detected"})
      test_pid = self()

      mock_loader = fn _id -> device end

      mock_module = spawn_mock_pipeline(test_pid)

      Executor.evaluate(event,
        pipeline_module: mock_module,
        device_loader: mock_loader
      )

      assert_received {:start_recording, _device}
    end

    test "logs warning when device not found", %{device: device} do
      full_trigger_fixture(device, %{
        event_type: "motion_detected",
        target_type: "start_recording"
      })

      {:ok, event} = Events.create_event(device, %{"type" => "motion_detected"})

      log =
        capture_log([level: :warning], fn ->
          Executor.evaluate(event, device_loader: fn _id -> nil end)
        end)

      assert log =~ "cannot start recording"
      assert log =~ "not found"
    end
  end

  describe "evaluate/2 with stop_recording target" do
    test "calls pipeline stop_recording", %{device: device} do
      full_trigger_fixture(device, %{
        event_type: "motion_ended",
        target_type: "stop_recording"
      })

      {:ok, event} = Events.create_event(device, %{"type" => "motion_ended"})
      test_pid = self()

      mock_module = spawn_mock_pipeline(test_pid)

      Executor.evaluate(event,
        pipeline_module: mock_module,
        device_loader: fn _id -> device end
      )

      assert_received {:stop_recording, _device}
    end

    test "logs warning when device not found", %{device: device} do
      full_trigger_fixture(device, %{
        event_type: "motion_ended",
        target_type: "stop_recording"
      })

      {:ok, event} = Events.create_event(device, %{"type" => "motion_ended"})

      log =
        capture_log([level: :warning], fn ->
          Executor.evaluate(event, device_loader: fn _id -> nil end)
        end)

      assert log =~ "cannot stop recording"
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
        target_type: "start_recording",
        config: %{}
      })

      ExNVR.Triggers.set_device_trigger_configs(device.id, [trigger.id])

      {:ok, event} = Events.create_event(device, %{"type" => "multi_test"})
      test_pid = self()
      mock_module = spawn_mock_pipeline(test_pid)

      log =
        capture_log([level: :warning], fn ->
          Executor.evaluate(event,
            pipeline_module: mock_module,
            device_loader: fn _id -> device end
          )
        end)

      assert log =~ "LOG_TARGET:"
      assert_received {:start_recording, _device}
    end
  end

  defp spawn_mock_pipeline(test_pid) do
    # Create a module dynamically that sends messages to test process
    module_name = :"MockPipeline_#{System.unique_integer([:positive])}"

    Module.create(
      module_name,
      quote do
        def start_recording(device) do
          send(unquote(test_pid), {:start_recording, device})
          :ok
        end

        def stop_recording(device) do
          send(unquote(test_pid), {:stop_recording, device})
          :ok
        end
      end,
      Macro.Env.location(__ENV__)
    )

    module_name
  end
end
