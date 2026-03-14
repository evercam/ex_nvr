defmodule ExNVR.Triggers.Executor do
  @moduledoc """
  Executes trigger target actions for a matched event.
  """

  require Logger

  alias ExNVR.Devices
  alias ExNVR.Events.Event
  alias ExNVR.Triggers
  alias ExNVR.Triggers.TriggerTargetConfig

  @doc """
  Evaluate triggers for the given event. Finds matching trigger configs
  for the event's device and type, then executes all enabled targets.
  """
  @spec evaluate(Event.t(), keyword()) :: :ok
  def evaluate(event, opts \\ [])

  def evaluate(%Event{device_id: nil}, _opts), do: :ok

  def evaluate(%Event{} = event, opts) do
    device_loader = Keyword.get(opts, :device_loader, &Devices.get/1)
    state_updater = Keyword.get(opts, :state_updater, &Devices.update_state/2)

    triggers = Triggers.matching_triggers(event.device_id, event.type)

    Logger.info(
      "Trigger executor: found #{length(triggers)} matching trigger(s) for device=#{event.device_id} event_type=#{event.type}"
    )

    Enum.each(triggers, fn trigger_config ->
      trigger_config.target_configs
      |> Enum.filter(& &1.enabled)
      |> Enum.each(&execute_target(&1, event, device_loader, state_updater))
    end)
  end

  defp execute_target(
         %TriggerTargetConfig{target_type: "log_message"} = target,
         event,
         _loader,
         _updater
       ) do
    level = target.config["level"] || "info"
    prefix = target.config["message_prefix"] || "Trigger"

    level_atom = String.to_existing_atom(level)
    Logger.log(level_atom, "#{prefix}: #{inspect(event)}")
  end

  defp execute_target(
         %TriggerTargetConfig{target_type: "start_recording"},
         event,
         device_loader,
         state_updater
       ) do
    case device_loader.(event.device_id) do
      nil ->
        Logger.warning("Trigger: cannot start recording, device #{event.device_id} not found")

      device ->
        Logger.info("Trigger: starting recording for device #{device.id}")

        case state_updater.(device, :recording) do
          {:ok, _device} ->
            :ok

          {:error, reason} ->
            Logger.error("Trigger: failed to start recording: #{inspect(reason)}")
        end
    end
  end

  defp execute_target(
         %TriggerTargetConfig{target_type: "stop_recording"},
         event,
         device_loader,
         state_updater
       ) do
    case device_loader.(event.device_id) do
      nil ->
        Logger.warning("Trigger: cannot stop recording, device #{event.device_id} not found")

      device ->
        Logger.info("Trigger: stopping recording for device #{device.id}")

        case state_updater.(device, :stopped) do
          {:ok, _device} ->
            :ok

          {:error, reason} ->
            Logger.error("Trigger: failed to stop recording: #{inspect(reason)}")
        end
    end
  end

  defp execute_target(%TriggerTargetConfig{target_type: type}, _event, _loader, _updater) do
    Logger.warning("Trigger: unknown target type #{inspect(type)}")
  end
end
