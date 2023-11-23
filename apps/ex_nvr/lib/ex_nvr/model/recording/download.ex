defmodule ExNVR.Model.Recording.Download do
  @moduledoc false

  alias ExNVR.Model.Recording

  @type unix_timestamp_ms :: non_neg_integer()

  @type t :: %__MODULE__{
          path: Path.t(),
          start_date: unix_timestamp_ms(),
          end_date: unix_timestamp_ms()
        }

  defstruct path: nil, start_date: nil, end_date: nil

  @spec new(Recording.t(), Path.t()) :: t()
  def new(%Recording{} = recording, recording_path) do
    %__MODULE__{
      path: recording_path,
      start_date: DateTime.to_unix(recording.start_date, :millisecond),
      end_date: DateTime.to_unix(recording.end_date, :millisecond)
    }
  end
end
