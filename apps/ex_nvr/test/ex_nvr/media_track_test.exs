defmodule ExNVR.MediaTrackTest do
  @moduledoc false

  use ExUnit.Case

  @sdp """
  v=0
  o=- 1686826680075169 1686826680075169 IN IP4 192.168.1.100
  s=Media Presentation
  e=NONE
  b=AS:5050
  t=0 0
  a=control:rtsp://192.168.1.100:554/ISAPI/Streaming/channels/101/av_stream/
  m=video 0 RTP/AVP 96
  c=IN IP4 0.0.0.0
  b=AS:5000
  a=recvonly
  a=x-dimensions:3840,2160
  a=control:rtsp://192.168.1.100:554/ISAPI/Streaming/channels/101/av_stream/trackID=1
  a=rtpmap:96 H264/90000
  a=fmtp:96 profile-level-id=420029; packetization-mode=1; sprop-parameter-sets=Z01AM42NcB4AIf/gLcBAQFAAAD6AAAXcDoYACZHAAAOThwu8uNDAATI4AABycOF3lwo=,aO44gA==
  m=application 0 RTP/AVP 107
  c=IN IP4 0.0.0.0
  b=AS:50
  a=recvonly
  a=control:rtsp://192.168.1.100:554/ISAPI/Streaming/channels/101/av_stream/trackID=3
  a=rtpmap:107 isapi.metadata/90000
  a=Media_header:MEDIAINFO=494D4B48010300000400000100000000000000000000000081000000000000000000000000000000;
  a=appversion:1.0
  """

  @sdp_no_sps_pps """
  v=0
  o=- 1686826680075169 1686826680075169 IN IP4 192.168.1.100
  s=Media Presentation
  e=NONE
  b=AS:5050
  t=0 0
  a=control:rtsp://192.168.1.100:554/ISAPI/Streaming/channels/101/av_stream/
  m=video 0 RTP/AVP 96
  c=IN IP4 0.0.0.0
  b=AS:5000
  a=recvonly
  a=x-dimensions:3840,2160
  a=control:rtsp://192.168.1.100:554/ISAPI/Streaming/channels/101/av_stream/trackID=1
  a=rtpmap:96 H264/90000
  """

  test "H264 media track from SDP" do
    video_media = ExSDP.parse!(@sdp) |> get_video_attributes()
    media_track = ExNVR.MediaTrack.from_sdp(video_media)

    assert media_track.type == :video
    assert media_track.codec == :H264
    assert media_track.clock_rate == 90_000
    assert media_track.payload_type == 96

    assert media_track.sps ==
             Base.decode64!(
               "Z01AM42NcB4AIf/gLcBAQFAAAD6AAAXcDoYACZHAAAOThwu8uNDAATI4AABycOF3lwo="
             )

    assert media_track.pps == Base.decode64!("aO44gA==")
  end

  test "H264 media track from SDP with no sps/pps" do
    video_media = ExSDP.parse!(@sdp_no_sps_pps) |> get_video_attributes()
    media_track = ExNVR.MediaTrack.from_sdp(video_media)

    assert media_track.type == :video
    assert media_track.codec == :H264
    assert media_track.clock_rate == 90_000
    assert media_track.payload_type == 96

    assert media_track.sps == <<>>
    assert media_track.pps == <<>>
  end

  defp get_video_attributes(%ExSDP{media: media_list}) do
    media_list |> Enum.find(fn elem -> elem.type == :video end)
  end
end
