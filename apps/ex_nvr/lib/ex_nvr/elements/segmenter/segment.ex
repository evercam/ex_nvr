defmodule ExNVR.Elements.Segmenter.Segment do
  @moduledoc """
  A struct describing a segment (video chunk)
  """

  @type t :: %__MODULE__{
          start_date: DateTime.t(),
          end_date: DateTime.t(),
          duration: Membrane.Time.t(),
          path: Path.t() | nil,
          device_id: binary() | nil
        }

  @enforce_keys [:start_date]
  defstruct @enforce_keys ++ [end_date: nil, duration: 0, path: nil, device_id: nil]

  @spec new(Membrane.Time.t(), Membrane.Time.t()) :: t()
  def new(start_time, segment_duration) do
    %__MODULE__{
      start_date: Membrane.Time.to_datetime(start_time),
      end_date: Membrane.Time.to_datetime(start_time + segment_duration),
      duration: segment_duration
    }
  end
end
