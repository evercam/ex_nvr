defmodule ExNVR.Pipeline.Output.Storage.Segmenter.SegmentMetadata do
  @moduledoc """
  A struct representing metadata about a segment
  """

  @typedoc """
  Segement medata:

  `media_duration` - The duration of the segment calculated from the received frames duration.
  `wall_clock_duration` - The duration of the segment calculated from the system clock.
  `realtime_duration`- The duration of the segment calculated using the monotonic clock.
  `size`- The size of the segment in bytes.
  """
  @type t :: %__MODULE__{
          media_duration: Membrane.Time.t(),
          wall_clock_duration: Membrane.Time.t(),
          realtime_duration: Membrane.Time.t(),
          size: non_neg_integer()
        }

  defstruct media_duration: 0, wall_clock_duration: 0, realtime_duration: 0, size: 0
end
