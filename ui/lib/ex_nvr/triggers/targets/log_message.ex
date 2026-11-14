defmodule ExNVR.Triggers.Targets.LogMessage do
  @moduledoc """
  Trigger target that logs the event with a configurable level and prefix.
  """

  @behaviour ExNVR.Triggers.TriggerTarget

  require Logger

  @impl true
  def label, do: "Log Message"

  @impl true
  def config_fields do
    [
      %{
        name: :level,
        type: :select,
        label: "Log Level",
        required: false,
        default: "info",
        placeholder: nil,
        options: [
          {"Debug", "debug"},
          {"Info", "info"},
          {"Warning", "warning"},
          {"Error", "error"}
        ]
      },
      %{
        name: :message_prefix,
        type: :string,
        label: "Message Prefix",
        required: false,
        default: "Trigger",
        placeholder: "Trigger",
        options: nil
      }
    ]
  end

  @impl true
  def validate_config(config) do
    config = for {k, v} <- config, into: %{}, do: {to_string(k), v}
    level = config["level"] || "info"

    if level in ~w(debug info warning error) do
      {:ok, %{"level" => level, "message_prefix" => config["message_prefix"] || "Trigger"}}
    else
      {:error, [level: "must be one of: debug, info, warning, error"]}
    end
  end

  @impl true
  def execute(trigger, config, _opts) do
    level = String.to_existing_atom(config["level"] || "info")
    prefix = config["message_prefix"] || "Trigger"
    Logger.log(level, "#{prefix}: #{inspect(trigger)}")
    :ok
  end
end
