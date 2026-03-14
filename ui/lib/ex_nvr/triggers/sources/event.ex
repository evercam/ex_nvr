defmodule ExNVR.Triggers.Sources.Event do
  @moduledoc """
  Trigger source that matches webhook events by type.
  """

  @behaviour ExNVR.Triggers.TriggerSource

  @impl true
  def label, do: "Event"

  @impl true
  def config_fields do
    [
      %{
        name: :event_type,
        type: :string,
        label: "Event Type",
        required: true,
        default: nil,
        placeholder: "e.g. motion_detected",
        options: nil
      }
    ]
  end

  @impl true
  def validate_config(config) do
    config = for {k, v} <- config, into: %{}, do: {to_string(k), v}
    event_type = config["event_type"]

    if is_binary(event_type) and event_type != "" do
      {:ok, %{"event_type" => event_type}}
    else
      {:error, [event_type: "is required"]}
    end
  end

  @impl true
  def matches?(source_config, event) do
    source_config["event_type"] == event.type
  end
end
