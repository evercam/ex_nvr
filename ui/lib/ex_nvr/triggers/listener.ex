defmodule ExNVR.Triggers.Listener do
  @moduledoc """
  Subscribes to trigger-producing PubSub topics, matches incoming messages
  against configured trigger sources, and executes the corresponding targets.
  """

  use GenServer

  require Logger

  alias ExNVR.Triggers
  alias ExNVR.Triggers.TriggerTargets

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(ExNVR.PubSub, Triggers.events_topic())
    Phoenix.PubSub.subscribe(ExNVR.PubSub, Triggers.detections_topic())
    {:ok, %{}}
  end

  @impl true
  def handle_info({:event_created, %{device_id: device_id}} = trigger, state) do
    evaluate(device_id, trigger)
    {:noreply, state}
  catch
    kind, reason ->
      Logger.error("Trigger listener error: #{Exception.format(kind, reason)}")
      {:noreply, state}
  end

  @impl true
  def handle_info({:detections, device_id, _dims, [_ | _]} = trigger, state) do
    evaluate(device_id, trigger)
    {:noreply, state}
  catch
    kind, reason ->
      Logger.error("Trigger listener error: #{Exception.format(kind, reason)}")
      {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp evaluate(nil, _trigger), do: :ok

  defp evaluate(device_id, trigger) do
    matching = Triggers.matching_triggers(device_id, trigger)

    Enum.each(matching, fn trigger_config ->
      trigger_config.target_configs
      |> Enum.filter(& &1.enabled)
      |> Enum.each(&execute_target(&1, trigger, device_id))
    end)
  end

  defp execute_target(target_config, trigger, device_id) do
    case TriggerTargets.module_for(target_config.target_type) do
      nil ->
        Logger.warning("Trigger: unknown target type #{inspect(target_config.target_type)}")

      module ->
        opts = [target_config_id: target_config.id, device_id: device_id]
        module.execute(trigger, target_config.config, opts)
    end
  end
end
