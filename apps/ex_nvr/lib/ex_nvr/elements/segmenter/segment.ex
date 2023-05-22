defmodule ExNVR.Elements.Segmenter.Segment do
  @moduledoc """
  A struct describing a segment (video chunk)
  """

  @type t :: %__MODULE__{
          start_date: DateTime.t(),
          end_date: DateTime.t(),
          duration: Membrane.Time.t(),
          path: Path.t(),
          device_id: binary()
        }

  @enforce_keys [:start_date]
  defstruct @enforce_keys ++ [end_date: nil, duration: 0, path: nil, device_id: nil]
end
