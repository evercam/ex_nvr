defmodule ExNVR.Pipeline.Output.Storage.Segmenter.Segment do
  @moduledoc """
  A struct describing a segment (video chunk)
  """

  alias ExNVR.Pipeline.Output.Storage.Segmenter.SegmentMetadata

  @type t :: %__MODULE__{
          start_date: Membrane.Time.t(),
          end_date: Membrane.Time.t(),
          duration: Membrane.Time.t(),
          path: Path.t() | nil,
          device_id: binary() | nil,
          metadata: SegmentMetadata.t(),
          wallclock_end_date: Membrane.Time.t() | nil
        }

  @enforce_keys [:start_date]
  defstruct @enforce_keys ++
              [
                end_date: 0,
                duration: 0,
                path: nil,
                device_id: nil,
                metadata: %SegmentMetadata{},
                wallclock_end_date: nil
              ]

  @spec new(Membrane.Time.t()) :: t()
  def new(start_time) do
    %__MODULE__{
      start_date: start_time,
      end_date: start_time,
      duration: 0
    }
  end

  @spec start_date(t()) :: Membrane.Time.t()
  def start_date(segment), do: segment.start_date

  @spec end_date(t()) :: Membrane.Time.t()
  def end_date(segment), do: segment.end_date

  @spec duration(t()) :: Membrane.Time.t()
  def duration(segment), do: segment.duration

  @spec wall_clock_duration(t()) :: Membrane.Time.t()
  def wall_clock_duration(segment), do: segment.metadata.wall_clock_duration

  @spec realtime_duration(t()) :: Membrane.Time.t()
  def realtime_duration(segment), do: segment.metadata.realtime_duration

  @spec size(t()) :: non_neg_integer()
  def size(segment), do: segment.metadata.size

  @spec add_duration(t(), Membrane.Time.t()) :: t()
  def add_duration(segment, duration) do
    current_duration = segment.duration + duration

    %__MODULE__{
      segment
      | end_date: segment.end_date + duration,
        duration: current_duration,
        metadata: %SegmentMetadata{segment.metadata | media_duration: current_duration}
    }
  end

  @spec with_wall_clock_duration(t(), Membrane.Time.t()) :: t()
  def with_wall_clock_duration(segment, wall_clock_duration) do
    %__MODULE__{
      segment
      | metadata: %SegmentMetadata{segment.metadata | wall_clock_duration: wall_clock_duration}
    }
  end

  @spec with_realtime_duration(t(), Membrane.Time.t()) :: t()
  def with_realtime_duration(segment, realtime_duration) do
    %__MODULE__{
      segment
      | metadata: %SegmentMetadata{segment.metadata | realtime_duration: realtime_duration}
    }
  end

  @doc """
  Add the size in bytes to the overall size of the segment
  """
  @spec add_size(t(), non_neg_integer()) :: t()
  def add_size(segment, size_in_bytes) do
    current_size = segment.metadata.size

    %__MODULE__{
      segment
      | metadata: %SegmentMetadata{segment.metadata | size: current_size + size_in_bytes}
    }
  end
end
