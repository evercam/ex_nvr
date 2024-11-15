defmodule ExNVRWeb.PromEx.Device do
  @moduledoc false

  use PromEx.Plugin

  alias ExNVR.Devices
  alias PromEx.MetricTypes.Polling

  @device_status_event [:ex_nvr, :device, :state]
  @camera_info_event [:ex_nvr, :camera, :info]
  @camera_stream_info_event [:ex_nvr, :camera, :stream, :info]

  @stream_tags [
    :device_id,
    :id,
    :enabled,
    :codec,
    :profile,
    :width,
    :height,
    :bitrate,
    :bitrate_mode,
    :frame_rate,
    :smart_codec
  ]

  @camera_info_tags [:device_id, :vendor, :model, :serial, :firmware_version]

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 15_000)

    [
      device_state_metrics(poll_rate),
      camera_config_metrics(poll_rate)
    ]
  end

  defp device_state_metrics(poll_rate) do
    Polling.build(
      :device_status_polling_events,
      poll_rate,
      {__MODULE__, :device_status, []},
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

  defp camera_config_metrics(poll_rate) do
    Polling.build(
      :device_stream_config_polling_events,
      poll_rate,
      {__MODULE__, :device_stream_config, []},
      [
        last_value(
          @camera_info_event,
          event_name: @camera_info_event,
          description: "The camera information",
          measurement: :value,
          tags: @camera_info_tags
        ),
        last_value(
          @camera_stream_info_event,
          event_name: @camera_stream_info_event,
          description: "The camera stream information",
          measurement: :value,
          tags: @stream_tags
        )
      ]
    )
  end

  @doc false
  def device_status() do
    Enum.each(ExNVR.Devices.list(), &execute/1)
  end

  @doc false
  def device_stream_config() do
    ip_cameras = ExNVR.Devices.ip_cameras()
    Enum.each(ip_cameras, &execute_device_info/1)
    Enum.each(ip_cameras, &execute_stream_config/1)
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

  defp execute_stream_config(device) do
    with {:ok, streams} <- Devices.stream_profiles(device) do
      for stream <- streams do
        metadata = Map.put(stream, :device_id, device.id)
        :telemetry.execute(@camera_stream_info_event, %{value: 1}, metadata)
      end
    end
  end

  defp execute_device_info(device) do
    with {:ok, device_info} <- Devices.device_info(device) do
      metadata = Map.put(device_info, :device_id, device.id)
      :telemetry.execute(@camera_info_event, %{value: 1}, metadata)
    end
  end
end
