defmodule ExNVRWeb.PromEx.Device do
  @moduledoc false

  use PromEx.Plugin

  alias PromEx.MetricTypes.Polling

  @device_status_event [:ex_nvr, :device, :state]

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 3_000)

    [
      device_state_metrics(poll_rate)
    ]
  end

  defp device_state_metrics(poll_rate) do
    Polling.build(
      :device_status_polling_events,
      poll_rate,
      {__MODULE__, :execute_device_status_metrics, []},
      [
        last_value(
          @device_status_event,
          event_name: @device_status_event,
          description: "The device state",
          measurement: :value,
          tags: [:device_id, :state]
        )
      ]
    )
  end

  @doc false
  def execute_device_status_metrics() do
    Enum.each(ExNVR.Devices.list(), &execute/1)
  end

  defp execute(device) do
    Enum.each(ExNVR.Model.Device.states(), fn state ->
      value = if device.state == state, do: 1, else: 0

      :telemetry.execute(@device_status_event, %{value: value}, %{
        device_id: device.id,
        state: state
      })
    end)
  end
end
