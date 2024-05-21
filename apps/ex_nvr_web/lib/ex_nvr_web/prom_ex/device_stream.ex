defmodule ExNVRWeb.PromEx.DeviceStream do
  @moduledoc false

  use PromEx.Plugin

  alias PromEx.MetricTypes.Event

  @info_event [:ex_nvr, :device, :stream]
  @frame_event [:ex_nvr, :device, :stream, :frame]

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :ex_nvr_device_stream_event_metrics,
      [
        last_value(
          "ex_nvr.device.stream.info",
          event_name: @info_event,
          description: "The device stream information",
          measurement: [:value],
          tags: [:device_id, :stream, :type, :codec, :profile, :width, :height]
        ),
        last_value(
          "ex_nvr.device.stream.gop_size",
          event_name: @frame_event,
          description: "Group of Picture size of the stream",
          measurement: :gop_size,
          tags: [:device_id, :stream]
        ),
        counter(
          "ex_nvr.device.stream.frames.total",
          event_name: @frame_event,
          description: "Total frames of the stream",
          measurement: :total_frames,
          tags: [:device_id, :stream]
        ),
        sum(
          "ex_nvr.device.stream.receive.bytes.total",
          event_name: @frame_event,
          description: "Total bytes received from the stream",
          measurement: :size,
          tags: [:device_id, :stream]
        )
      ]
    )
  end
end
