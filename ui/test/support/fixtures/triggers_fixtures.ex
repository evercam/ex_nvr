defmodule ExNVR.TriggersFixtures do
  @moduledoc """
  Test helpers for creating trigger entities.
  """

  alias ExNVR.Triggers

  @spec trigger_config_fixture(map()) :: Triggers.TriggerConfig.t()
  def trigger_config_fixture(attrs \\ %{}) do
    {:ok, config} =
      attrs
      |> Enum.into(%{
        name: "trigger_#{System.unique_integer([:monotonic, :positive])}",
        enabled: true
      })
      |> Triggers.create_trigger_config()

    config
  end

  @spec source_config_fixture(Triggers.TriggerConfig.t(), map()) ::
          Triggers.TriggerSourceConfig.t()
  def source_config_fixture(%Triggers.TriggerConfig{} = trigger_config, attrs \\ %{}) do
    {:ok, source} =
      attrs
      |> Enum.into(%{
        trigger_config_id: trigger_config.id,
        source_type: "event",
        config: %{"event_type" => "motion_detected"}
      })
      |> Triggers.create_source_config()

    source
  end

  @spec target_config_fixture(Triggers.TriggerConfig.t(), map()) ::
          Triggers.TriggerTargetConfig.t()
  def target_config_fixture(%Triggers.TriggerConfig{} = trigger_config, attrs \\ %{}) do
    {:ok, target} =
      attrs
      |> Enum.into(%{
        trigger_config_id: trigger_config.id,
        target_type: "log_message",
        config: %{"level" => "info", "message_prefix" => "Test trigger"},
        enabled: true
      })
      |> Triggers.create_target_config()

    target
  end

  @doc """
  Creates a complete trigger config with source, target, and device association.
  """
  @spec full_trigger_fixture(ExNVR.Model.Device.t(), map()) :: Triggers.TriggerConfig.t()
  def full_trigger_fixture(device, attrs \\ %{}) do
    event_type = attrs[:event_type] || "motion_detected"
    target_type = attrs[:target_type] || "log_message"

    target_config =
      attrs[:target_config] || %{"level" => "info", "message_prefix" => "Trigger fired"}

    trigger = trigger_config_fixture(Map.take(attrs, [:name, :enabled]))
    source_config_fixture(trigger, %{config: %{"event_type" => event_type}})

    target_config_fixture(trigger, %{
      target_type: target_type,
      config: target_config
    })

    Triggers.set_device_trigger_configs(device.id, [trigger.id])

    Triggers.get_trigger_config!(trigger.id)
  end
end
