defmodule ExNVR.Triggers.Executor do
  @moduledoc """
  Executes trigger target actions for a matched event.
  """

  require Logger

  alias ExNVR.Events.Event
  alias ExNVR.Triggers
  alias ExNVR.Triggers.TriggerTargetConfig

  @type pipeline_module :: module()

  @doc """
  Evaluate triggers for the given event. Finds matching trigger configs
  for the event's device and type, then executes all enabled targets.
  """
  @spec evaluate(Event.t(), keyword()) :: :ok
  def evaluate(event, opts \\ [])

  def evaluate(%Event{device_id: nil}, _opts), do: :ok

  def evaluate(%Event{} = event, opts) do
    pipeline_module = Keyword.get(opts, :pipeline_module, ExNVR.Pipelines.Main)
    device_loader = Keyword.get(opts, :device_loader, &ExNVR.Devices.get/1)

    triggers = Triggers.matching_triggers(event.device_id, event.type)

    Enum.each(triggers, fn trigger_config ->
      trigger_config.target_configs
      |> Enum.filter(& &1.enabled)
      |> Enum.each(&execute_target(&1, event, pipeline_module, device_loader))
    end)
  end

  defp execute_target(
         %TriggerTargetConfig{target_type: "log_message"} = target,
         event,
         _pipeline,
         _loader
       ) do
    level = target.config["level"] || "info"
    prefix = target.config["message_prefix"] || "Trigger"

    level_atom = String.to_existing_atom(level)
    Logger.log(level_atom, "#{prefix}: #{inspect(event)}")
  end

  defp execute_target(
         %TriggerTargetConfig{target_type: "start_recording"},
         event,
         pipeline_module,
         device_loader
       ) do
    case device_loader.(event.device_id) do
      nil ->
        Logger.warning("Trigger: cannot start recording, device #{event.device_id} not found")

      device ->
        Logger.info("Trigger: starting recording for device #{device.id}")

        try do
          pipeline_module.start_recording(device)
        rescue
          e -> Logger.error("Trigger: failed to start recording: #{Exception.message(e)}")
        end
    end
  end

  defp execute_target(
         %TriggerTargetConfig{target_type: "stop_recording"},
         event,
         pipeline_module,
         device_loader
       ) do
    case device_loader.(event.device_id) do
      nil ->
        Logger.warning("Trigger: cannot stop recording, device #{event.device_id} not found")

      device ->
        Logger.info("Trigger: stopping recording for device #{device.id}")

        try do
          pipeline_module.stop_recording(device)
        rescue
          e -> Logger.error("Trigger: failed to stop recording: #{Exception.message(e)}")
        end
    end
  end

  defp execute_target(%TriggerTargetConfig{target_type: type}, _event, _pipeline, _loader) do
    Logger.warning("Trigger: unknown target type #{inspect(type)}")
  end
end
