defmodule ExNVR.Triggers.Executor do
  @moduledoc """
  Executes trigger target actions for a matched event.

  Dispatches to the implementation module registered for each target type.
  """

  require Logger

  alias ExNVR.Events.Event
  alias ExNVR.Triggers
  alias ExNVR.Triggers.TriggerTargets

  @spec evaluate(Event.t(), keyword()) :: :ok
  def evaluate(event, opts \\ [])

  def evaluate(%Event{device_id: nil}, _opts), do: :ok

  def evaluate(%Event{} = event, opts) do
    triggers = Triggers.matching_triggers(event.device_id, event.type)

    Logger.info(
      "Trigger executor: found #{length(triggers)} matching trigger(s) " <>
        "for device=#{event.device_id} event_type=#{event.type}"
    )

    Enum.each(triggers, fn trigger_config ->
      trigger_config.target_configs
      |> Enum.filter(& &1.enabled)
      |> Enum.each(&execute_target(&1, event, opts))
    end)
  end

  defp execute_target(target_config, event, opts) do
    case TriggerTargets.module_for(target_config.target_type) do
      nil ->
        Logger.warning("Trigger: unknown target type #{inspect(target_config.target_type)}")

      module ->
        module.execute(event, target_config.config, opts)
    end
  end
end
