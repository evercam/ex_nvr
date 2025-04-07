defmodule ExNVR.RTSP.OnvifReplayExtension do
  @moduledoc """
  A module describing onvif replay rtp header extension
  """

  alias Membrane.Time

  @type t :: %__MODULE__{
          timestamp: DateTime.t(),
          keyframe?: boolean(),
          discontinuity?: boolean(),
          last_frame?: boolean()
        }

  defstruct [:timestamp, :keyframe?, :discontinuity?, :last_frame?]

  @spec decode(binary()) :: t()
  def decode(<<ntp_timestamp::binary-size(8), c::1, _e::1, d::1, t::1, _rest::28>>) do
    %__MODULE__{
      timestamp: Time.from_ntp_timestamp(ntp_timestamp) |> Time.to_datetime(),
      keyframe?: c == 1,
      discontinuity?: d == 1,
      last_frame?: t == 1
    }
  end
end
