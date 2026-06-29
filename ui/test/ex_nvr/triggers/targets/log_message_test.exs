defmodule ExNVR.Triggers.Targets.LogMessageTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias ExNVR.Triggers.Targets.LogMessage

  describe "label/0" do
    test "returns human-readable label" do
      assert LogMessage.label() == "Log Message"
    end
  end

  describe "config_fields/0" do
    test "returns level and message_prefix fields" do
      fields = LogMessage.config_fields()
      assert length(fields) == 2
      names = Enum.map(fields, & &1.name)
      assert :level in names
      assert :message_prefix in names
    end

    test "level field has select options" do
      field = Enum.find(LogMessage.config_fields(), &(&1.name == :level))
      assert field.type == :select
      values = Enum.map(field.options, &elem(&1, 1))
      assert "debug" in values
      assert "info" in values
      assert "warning" in values
      assert "error" in values
    end
  end

  describe "validate_config/1" do
    test "accepts valid config" do
      assert {:ok, %{"level" => "warning", "message_prefix" => "Test"}} =
               LogMessage.validate_config(%{"level" => "warning", "message_prefix" => "Test"})
    end

    test "accepts atom keys" do
      assert {:ok, %{"level" => "info", "message_prefix" => "Hello"}} =
               LogMessage.validate_config(%{level: "info", message_prefix: "Hello"})
    end

    test "defaults level to info" do
      assert {:ok, %{"level" => "info"}} = LogMessage.validate_config(%{})
    end

    test "defaults message_prefix to Trigger" do
      assert {:ok, %{"message_prefix" => "Trigger"}} = LogMessage.validate_config(%{})
    end

    test "rejects invalid level" do
      assert {:error, [level: _]} = LogMessage.validate_config(%{"level" => "critical"})
    end
  end

  describe "execute/3" do
    test "logs with configured level and prefix" do
      event = %ExNVR.Events.Event{type: "test_event"}
      config = %{"level" => "warning", "message_prefix" => "ALERT"}

      log =
        capture_log([level: :warning], fn ->
          assert :ok = LogMessage.execute(event, config, [])
        end)

      assert log =~ "ALERT:"
      assert log =~ "test_event"
    end

    test "uses default prefix when not configured" do
      event = %ExNVR.Events.Event{type: "test_event"}
      config = %{"level" => "error"}

      log =
        capture_log([level: :error], fn ->
          assert :ok = LogMessage.execute(event, config, [])
        end)

      assert log =~ "Trigger:"
    end
  end
end
