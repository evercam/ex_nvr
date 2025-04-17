defmodule ExNVR.Pipeline.Track.Stat do
  @moduledoc false

  @type t :: %__MODULE__{
          width: non_neg_integer() | nil,
          height: non_neg_integer() | nil,
          profile: binary(),
          recv_bytes: non_neg_integer(),
          total_frames: non_neg_integer(),
          gop_size: non_neg_integer()
        }

  @derive Jason.Encoder
  defstruct [:width, :height, :profile, :recv_bytes, :total_frames, :gop_size]
end
