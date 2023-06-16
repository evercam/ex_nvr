defmodule ExNVR.MediaTrack do
  @moduledoc """
  A struct that contains metadata about a media track received from a device.

  It may contains information gathered from multiple sources:
    * Session Description Protocol (SDP) from RTSP
    * Metrics calculated from the stream (e.g. bitrate, framerate, ...etc.)
    * Information got through the device API if available (e.g. ONVIF)
  """

  @type t :: %__MODULE__{
          type: :video | :audio,
          width: pos_integer(),
          height: pos_integer(),
          profile: Membrane.H264.profile_t(),
          codec: :H264,
          sps: binary(),
          pps: binary(),
          bitrate: non_neg_integer(),
          framerate: Membrane.H264.framerate_t(),
          clock_rate: pos_integer(),
          payload_type: pos_integer(),
          control: binary()
        }

  @enforce_keys [:type]
  defstruct @enforce_keys ++
              [
                width: nil,
                height: nil,
                profile: nil,
                codec: :H264,
                sps: nil,
                pps: nil,
                bitrate: nil,
                framerate: nil,
                clock_rate: 0,
                payload_type: nil,
                control: nil
              ]

  @spec from_sdp(ExSDP.Media.t()) :: t()
  def from_sdp(%ExSDP.Media{} = media) do
    rtpmap = get_attribute(media, ExSDP.Attribute.RTPMapping)
    fmtp = get_attribute(media, ExSDP.Attribute.FMTP)

    codec = String.to_atom(rtpmap.encoding)

    %__MODULE__{
      type: media.type,
      codec: codec,
      clock_rate: rtpmap.clock_rate,
      payload_type: rtpmap.payload_type,
      control: get_attribute(media, "control", ""),
      sps: sps(codec, fmtp),
      pps: pps(codec, fmtp)
    }
  end

  defp sps(:H264, %{sprop_parameter_sets: parameter_sets}),
    do: Map.get(parameter_sets, :sps, <<>>)

  defp sps(_, _), do: <<>>

  defp pps(:H264, %{sprop_parameter_sets: parameter_sets}),
    do: Map.get(parameter_sets, :pps, <<>>)

  defp pps(_, _), do: <<>>

  defp get_attribute(video_attributes, attribute, default \\ nil) do
    case ExSDP.Media.get_attribute(video_attributes, attribute) do
      {^attribute, value} -> value
      %^attribute{} = value -> value
      _other -> default
    end
  end
end
