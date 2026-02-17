defmodule ExNVRWeb.PromEx.Recording do
  @moduledoc false

  use PromEx.Plugin

  alias PromEx.MetricTypes.Event

  @recording_event [:ex_nvr, :recordings, :stop]

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :ex_nvr_recordings_event_metrics,
      [
        counter("ex_nvr.recording.total",
          event_name: @recording_event,
          measurement: fn _measurement -> 1 end,
          description: "The total number of recorded segments",
          tags: [:device_id, :stream]
        ),
        distribution("ex_nvr.recording.duration.milliseconds",
          event_name: @recording_event,
          measurement: :duration,
          description: "The total duration of the recordings",
          tags: [:device_id, :stream],
          reporter_options: [
            buckets: [60_500, 65_000, 70_000, 75_000]
          ]
        ),
        distribution("ex_nvr.recording.size.bytes",
          event_name: @recording_event,
          measurement: :size,
          description: "The total size of the recordings",
          tags: [:device_id, :stream],
          reporter_options: [
            buckets: [500_000, 1_000_000, 5_000_000, 10_000_000, 20_000_000, 40_000_000]
          ]
        )
      ]
    )
  end
end
