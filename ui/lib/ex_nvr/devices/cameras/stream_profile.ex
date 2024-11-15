defmodule ExNVR.Devices.Cameras.StreamProfile do
  @moduledoc false

  @type t :: %__MODULE__{
          id: binary() | non_neg_integer(),
          enabled: boolean(),
          name: binary(),
          codec: binary(),
          profile: nil | binary(),
          width: non_neg_integer(),
          height: non_neg_integer(),
          frame_rate: number(),
          bitrate: non_neg_integer(),
          bitrate_mode: binary(),
          gop: non_neg_integer(),
          smart_codec: boolean()
        }

  defstruct [
    :id,
    :name,
    :codec,
    :profile,
    :width,
    :height,
    :frame_rate,
    :bitrate,
    :bitrate_mode,
    :gop,
    enabled: false,
    smart_codec: false
  ]
end
