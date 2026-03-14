defmodule ExNVR.Triggers.ListenerTest do
  use ExNVR.DataCase

  import ExUnit.CaptureLog
  import ExNVR.DevicesFixtures
  import ExNVR.TriggersFixtures

  alias ExNVR.Events
  alias ExNVR.Triggers

  @moduletag :tmp_dir

  setup ctx do
    device = camera_device_fixture(ctx.tmp_dir)
    %{device: device}
  end

  describe "event broadcast integration" do
    test "creating an event broadcasts on PubSub", %{device: device} do
      Phoenix.PubSub.subscribe(ExNVR.PubSub, Triggers.events_topic())

      {:ok, event} =
        Events.create_event(device, %{"type" => "test_broadcast", "metadata" => %{}})

      assert_receive {:event_created, ^event}
    end

    test "listener evaluates triggers when event is created", %{device: device} do
      full_trigger_fixture(device, %{
        event_type: "listener_test",
        target_type: "log_message",
        target_config: %{"level" => "warning", "message_prefix" => "LISTENER_TEST"}
      })

      # Start a listener for this test
      start_supervised!(Triggers.Listener)
      # Allow the listener to access the sandbox
      Ecto.Adapters.SQL.Sandbox.allow(ExNVR.Repo, self(), Process.whereis(Triggers.Listener))

      log =
        capture_log([level: :warning], fn ->
          {:ok, _event} = Events.create_event(device, %{"type" => "listener_test"})
          # Give the listener time to process the message
          Process.sleep(100)
        end)

      assert log =~ "LISTENER_TEST:"
    end

    test "listener ignores events without matching triggers", %{device: device} do
      start_supervised!(Triggers.Listener)
      Ecto.Adapters.SQL.Sandbox.allow(ExNVR.Repo, self(), Process.whereis(Triggers.Listener))

      log =
        capture_log([level: :warning], fn ->
          {:ok, _event} = Events.create_event(device, %{"type" => "no_trigger_for_this"})
          Process.sleep(100)
        end)

      refute log =~ "Trigger:"
      refute log =~ "LISTENER_TEST:"
    end
  end
end
