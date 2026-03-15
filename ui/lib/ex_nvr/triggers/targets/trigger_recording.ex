defmodule ExNVR.Triggers.Targets.TriggerRecording do
  @moduledoc """
  Trigger target that signals the VideoBufferer to start forwarding frames.

  When executed, broadcasts an event on the device's PubSub topic so that
  the `VideoBufferer` element flushes its circular buffer and enters
  forwarding mode.
  """

  @behaviour ExNVR.Triggers.TriggerTarget

  require Logger

  @impl true
  def label, do: "Trigger Recording"

  @impl true
  def config_fields, do: []

  @impl true
  def validate_config(_config), do: {:ok, %{}}

  @impl true
  def execute(event, _config, _opts) do
    Logger.info("Trigger: signaling video bufferer for device #{event.device_id}")

    Phoenix.PubSub.broadcast(
      ExNVR.PubSub,
      "events:#{event.device_id}",
      {:event, "recording_triggered"}
    )
  end
end
