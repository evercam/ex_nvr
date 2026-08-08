defmodule ExNVR.Triggers.Targets.TriggerRecordingTest do
  @moduledoc false

  use ExUnit.Case

  alias ExNVR.Triggers.Targets.TriggerRecording

  describe "validate_config/1" do
    test "accepts valid config with defaults" do
      assert {:ok, config} = TriggerRecording.validate_config(%{})
      assert config["event_timeout"] == 30
      assert config["buffer_limit_type"] == "keyframes"
      assert config["buffer_limit_value"] == 3
    end

    test "accepts valid explicit values" do
      input = %{
        "event_timeout" => 60,
        "buffer_limit_type" => "seconds",
        "buffer_limit_value" => 10
      }

      assert {:ok, config} = TriggerRecording.validate_config(input)
      assert config["event_timeout"] == 60
      assert config["buffer_limit_type"] == "seconds"
      assert config["buffer_limit_value"] == 10
    end

    test "parses string integers" do
      input = %{"event_timeout" => "45", "buffer_limit_value" => "10"}
      assert {:ok, config} = TriggerRecording.validate_config(input)
      assert config["event_timeout"] == 45
      assert config["buffer_limit_value"] == 10
    end

    test "rejects zero buffer_limit_value" do
      input = %{"buffer_limit_value" => 0}
      assert {:error, errors} = TriggerRecording.validate_config(input)
      assert Keyword.has_key?(errors, :buffer_limit_value)
    end

    test "rejects negative buffer_limit_value" do
      input = %{"buffer_limit_value" => -1}
      assert {:error, errors} = TriggerRecording.validate_config(input)
      assert Keyword.has_key?(errors, :buffer_limit_value)
    end

    test "rejects zero event_timeout" do
      input = %{"event_timeout" => 0}
      assert {:error, errors} = TriggerRecording.validate_config(input)
      assert Keyword.has_key?(errors, :event_timeout)
    end

    test "rejects negative event_timeout" do
      input = %{"event_timeout" => -5}
      assert {:error, errors} = TriggerRecording.validate_config(input)
      assert Keyword.has_key?(errors, :event_timeout)
    end

    test "reports both errors when both values are invalid" do
      input = %{"event_timeout" => 0, "buffer_limit_value" => 0}
      assert {:error, errors} = TriggerRecording.validate_config(input)
      assert Keyword.has_key?(errors, :event_timeout)
      assert Keyword.has_key?(errors, :buffer_limit_value)
    end
  end

  describe "to_bufferer_opts/1" do
    test "converts seconds config to milliseconds for bufferer" do
      config = %{
        "event_timeout" => 45,
        "buffer_limit_type" => "seconds",
        "buffer_limit_value" => 10
      }

      opts = TriggerRecording.to_bufferer_opts(config)
      assert opts[:event_timeout] == 45_000
      assert opts[:limit] == {:seconds, 10}
    end

    test "defaults to keyframes for unknown limit type" do
      config = %{"buffer_limit_type" => "unknown", "buffer_limit_value" => 5}
      opts = TriggerRecording.to_bufferer_opts(config)
      assert opts[:limit] == {:keyframes, 5}
    end

    test "defaults event_timeout to 30s (30_000ms)" do
      config = %{}
      opts = TriggerRecording.to_bufferer_opts(config)
      assert opts[:event_timeout] == 30_000
    end
  end
end
