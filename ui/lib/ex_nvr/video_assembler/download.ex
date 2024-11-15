defmodule ExNVR.VideoAssembler.Download do
  @moduledoc false

  @type unix_timestamp_ms :: non_neg_integer()

  @type t :: %__MODULE__{
          path: Path.t(),
          start_date: unix_timestamp_ms(),
          end_date: unix_timestamp_ms()
        }

  defstruct path: nil, start_date: nil, end_date: nil

  @spec new(DateTime.t(), DateTime.t(), Path.t()) :: t()
  def new(start_date, end_date, recording_path) do
    %__MODULE__{
      path: recording_path,
      start_date: DateTime.to_unix(start_date, :millisecond),
      end_date: DateTime.to_unix(end_date, :millisecond)
    }
  end
end
