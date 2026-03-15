defmodule ExNVR.Triggers.Targets.TriggerRecording do
  @moduledoc """
  Trigger target that configures a `VideoBufferer` in the Membrane pipeline
  and signals it to start forwarding frames when the trigger fires.

  Each target config instance gets its own VideoBufferer + Storage branch
  in the pipeline, with independently configurable buffer settings.

  The config is read by the pipeline at setup time via `to_bufferer_opts/1`.
  At runtime, `execute/3` broadcasts on a target-config-specific PubSub topic
  so only the matching VideoBufferer is signalled.
  """

  @behaviour ExNVR.Triggers.TriggerTarget

  require Logger

  @impl true
  def label, do: "Trigger Recording"

  @impl true
  def config_fields do
    [
      %{
        name: :event_timeout,
        type: :integer,
        label: "Event timeout (ms)",
        required: false,
        default: 30_000,
        placeholder: "30000",
        options: nil
      },
      %{
        name: :buffer_limit_type,
        type: :select,
        label: "Buffer limit type",
        required: false,
        default: "keyframes",
        placeholder: nil,
        options: [{"Keyframes", "keyframes"}, {"Seconds", "seconds"}, {"Bytes", "bytes"}]
      },
      %{
        name: :buffer_limit_value,
        type: :integer,
        label: "Buffer limit value",
        required: false,
        default: 3,
        placeholder: "3",
        options: nil
      }
    ]
  end

  @impl true
  def validate_config(config) do
    config = for {k, v} <- config, into: %{}, do: {to_string(k), v}

    {:ok,
     %{
       "event_timeout" => parse_int(config["event_timeout"], 30_000),
       "buffer_limit_type" => config["buffer_limit_type"] || "keyframes",
       "buffer_limit_value" => parse_int(config["buffer_limit_value"], 3)
     }}
  end

  @impl true
  def execute(event, _config, opts) do
    target_config_id = Keyword.fetch!(opts, :target_config_id)

    Logger.info(
      "Trigger: signaling video bufferer #{target_config_id} for device #{event.device_id}"
    )

    Phoenix.PubSub.broadcast(
      ExNVR.PubSub,
      topic(target_config_id),
      {:event, "recording_triggered"}
    )
  end

  @doc "PubSub topic for a specific target config instance."
  @spec topic(integer() | binary()) :: String.t()
  def topic(target_config_id), do: "trigger_recording:#{target_config_id}"

  @doc "Convert stored config map to VideoBufferer option values."
  @spec to_bufferer_opts(map()) :: Keyword.t()
  def to_bufferer_opts(config) do
    limit_type =
      case config["buffer_limit_type"] do
        "seconds" -> :seconds
        "bytes" -> :bytes
        _ -> :keyframes
      end

    [
      event_timeout: config["event_timeout"] || 30_000,
      limit: {limit_type, config["buffer_limit_value"] || 3}
    ]
  end

  defp parse_int(nil, default), do: default
  defp parse_int(val, _default) when is_integer(val), do: val

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(_, default), do: default
end
