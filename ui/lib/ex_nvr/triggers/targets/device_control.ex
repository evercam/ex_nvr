defmodule ExNVR.Triggers.Targets.DeviceControl do
  @moduledoc """
  Trigger target that controls device recording state.

  Supports starting, stopping, or toggling recording.
  """

  @behaviour ExNVR.Triggers.TriggerTarget

  require Logger

  @impl true
  def label, do: "Device Control"

  @impl true
  def config_fields do
    [
      %{
        name: :action,
        type: :select,
        label: "Action",
        required: true,
        default: "start",
        placeholder: nil,
        options: [
          {"Start Recording", "start"},
          {"Stop Recording", "stop"},
          {"Toggle Recording", "toggle"}
        ]
      }
    ]
  end

  @impl true
  def validate_config(config) do
    config = for {k, v} <- config, into: %{}, do: {to_string(k), v}
    action = config["action"] || "start"

    if action in ~w(start stop toggle) do
      {:ok, %{"action" => action}}
    else
      {:error, [action: "must be one of: start, stop, toggle"]}
    end
  end

  @impl true
  def execute(_trigger, config, opts) do
    device_id = Keyword.fetch!(opts, :device_id)
    device_loader = Keyword.get(opts, :device_loader, &ExNVR.Devices.get/1)
    state_updater = Keyword.get(opts, :state_updater, &ExNVR.Devices.update_state/2)
    action = config["action"] || "start"

    case device_loader.(device_id) do
      nil ->
        Logger.warning("Trigger: device #{device_id} not found")
        {:error, :device_not_found}

      device ->
        new_state = resolve_state(action, device)
        Logger.info("Trigger: #{action} recording for device #{device.id} (-> #{new_state})")

        case state_updater.(device, new_state) do
          {:ok, _device} ->
            :ok

          {:error, reason} ->
            Logger.error("Trigger: failed to #{action} recording: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp resolve_state("start", _device), do: :recording
  defp resolve_state("stop", _device), do: :stopped

  defp resolve_state("toggle", device) do
    if ExNVR.Model.Device.recording?(device), do: :stopped, else: :recording
  end
end
