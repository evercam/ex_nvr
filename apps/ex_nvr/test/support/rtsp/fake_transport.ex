defmodule ExNVR.RTSP.Transport.Fake do
  @moduledoc false
  use Membrane.RTSP.Transport

  @get_parameter_response "RTSP/1.0 200 OK\r\nCSeq: 4\r\n\r\n"

  @describe_response """
  RTSP/1.0 200 OK
  CSeq: 0
  Date: Wed, Aug 02 2023 22:20:54 GMT
  Content-Base: rtsp://192.168.1.190/main/
  Content-Type: application/sdp
  Content-Length: 597

  v=0
  o=- 1690996031877678 1 IN IP4 192.168.1.190
  s=RTSP/RTP stream from IPNC
  i=main
  t=0 0
  a=tool:LIVE555 Streaming Media v2010.07.29
  a=type:broadcast
  a=control:*
  a=range:npt=0-
  a=x-qt-text-nam:RTSP/RTP stream from IPNC
  a=x-qt-text-inf:main
  m=video 0 RTP/AVP 96
  b=AS:12000
  a=rtpmap:96 H264/90000
  a=fmtp:96 packetization-mode=1;profile-level-id=4D4033;sprop-parameter-sets=Z01AM42NQB4AIf/gLcBAQFAAAD6AAAPoDoYAMfwAADk4cLvLjQwAY/gAAHJw4XeXCg==,aO44gA==
  a=recvonly
  a=control:track1
  m=application 0 RTP/AVP 98
  b=AS:0
  a=rtpmap:98 vnd.onvif.metadata/90000
  a=recvonly
  a=control:track2
  """

  @setup_response "RTSP/1.0 200 OK\r\nCSeq: 5\r\nDate: Wed, Aug 02 2023 22:20:54 GMT\r\nTransport: RTP/AVP/TCP;unicast;destination=105.235.129.26;source=192.168.1.190;interleaved=0-1\r\nSession: D1F824DA\r\n\r\n"
  @play_response "RTSP/1.0 200 OK\r\nCSeq: 6\r\nDate: Wed, Aug 02 2023 22:20:54 GMT\r\nRange: npt=0.000-\r\nSession: D1F824DA\r\nRTP-Info: url=rtsp://192.168.1.190/main/track1;seq=53626;rtptime=1692503820,url=rtsp://192.168.1.190/main/track2;seq=0;rtptime=0\r\n\r\n"

  @rtp_packets "../../fixtures/rtp/video-30-10s.rtp" |> Path.expand(__DIR__)

  @impl true
  def execute(request, ref, _options \\ []) do
    # An ugly way of mocking tcp interactions
    resolver =
      Application.get_env(
        :ex_nvr,
        :tcp_socket_resolver,
        &__MODULE__.establish_session_without_media_packets/2
      )

    resolver.(request, ref)
  end

  @impl true
  def init(_url, options \\ []) do
    {:ok, options}
  end

  @impl true
  def close(_ref) do
    :ok
  end

  @spec perform_request(binary(), any(), Keyword.t()) ::
          {:ok, binary()} | {:error, term()}
  def perform_request(request, state, _options) do
    {:ok, establish_session_without_media_packets(request, state)}
  end

  @spec establish_session_without_media_packets(binary(), any()) :: {:ok, binary()}
  def establish_session_without_media_packets(request, _state) do
    {:ok, process_request(request)}
  end

  @spec establish_session_with_media_packets(binary(), any()) :: {:ok, binary()}
  def establish_session_with_media_packets(request, state) do
    response = process_request(request)

    if play?(request),
      do:
        spawn_link(fn -> emit_media_packets(state[:media_receiver], File.read!(@rtp_packets)) end)

    {:ok, response}
  end

  @spec establish_session_with_media_error(binary(), term()) :: {:ok, binary()}
  def establish_session_with_media_error(request, _state) do
    response = process_request(request)

    if play?(request) do
      spawn_link(fn ->
        Process.sleep(50)
        raise "unexpected error"
      end)
    end

    {:ok, response}
  end

  defp emit_media_packets(media_receiver, <<size::16, packet::binary-size(size), rest::binary>>) do
    send(media_receiver, {:media_packet, 0, packet})
    Process.sleep(10)
    emit_media_packets(media_receiver, rest)
  end

  defp emit_media_packets(_media_receiver, _data), do: :ok

  defp process_request(request) do
    case request do
      <<"DESCRIBE", _::binary>> -> @describe_response
      <<"GET_PARAMETER", _::binary>> -> @get_parameter_response
      <<"SETUP", _::binary>> -> @setup_response
      <<"PLAY", _::binary>> -> @play_response
    end
  end

  defp play?(<<"PLAY", _::binary>>), do: true
  defp play?(_request), do: false
end
