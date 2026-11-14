defmodule ExNVR.Triggers.Sources.EventTest do
  use ExUnit.Case, async: true

  alias ExNVR.Triggers.Sources.Event

  describe "label/0" do
    test "returns human-readable label" do
      assert Event.label() == "Event"
    end
  end

  describe "config_fields/0" do
    test "returns event_type field" do
      fields = Event.config_fields()
      assert length(fields) == 1
      assert %{name: :event_type, type: :string, required: true} = hd(fields)
    end
  end

  describe "validate_config/1" do
    test "accepts valid event_type" do
      assert {:ok, %{"event_type" => "motion_detected"}} =
               Event.validate_config(%{"event_type" => "motion_detected"})
    end

    test "accepts atom keys" do
      assert {:ok, %{"event_type" => "motion_detected"}} =
               Event.validate_config(%{event_type: "motion_detected"})
    end

    test "rejects missing event_type" do
      assert {:error, [event_type: _]} = Event.validate_config(%{})
    end

    test "rejects empty event_type" do
      assert {:error, [event_type: _]} = Event.validate_config(%{"event_type" => ""})
    end
  end

  describe "matches?/2" do
    test "matches when event type equals config event_type" do
      config = %{"event_type" => "motion_detected"}
      message = {:event_created, %{type: "motion_detected", device_id: "dev-1"}}
      assert Event.matches?(config, message)
    end

    test "does not match different event type" do
      config = %{"event_type" => "motion_detected"}
      message = {:event_created, %{type: "door_open", device_id: "dev-1"}}
      refute Event.matches?(config, message)
    end

    test "does not match non-event messages" do
      config = %{"event_type" => "motion_detected"}
      refute Event.matches?(config, {:detections, "dev-1", {640, 480}, []})
    end
  end
end
