defmodule ExNVR.Pipeline.Output.WebRTC do
  @moduledoc """
  Send video/audio via WebRTC.
  """

  use Membrane.Sink

  require Membrane.Logger

  import Bitwise

  alias ExNVR.Pipeline.Event.StreamClosed
  alias ExWebRTC.{MediaStreamTrack, PeerConnection, RTPCodecParameters, SessionDescription}
  alias Membrane.{H264, H265, Time}
  alias RTSP.RTP.Encoder

  @max_rtp_timestamp 1 <<< 32
  @clock_rate 90_000
  @h264_codec %RTPCodecParameters{
    payload_type: 96,
    mime_type: "video/H264",
    clock_rate: @clock_rate,
    sdp_fmtp_line: %ExSDP.Attribute.FMTP{
      pt: 96,
      level_asymmetry_allowed: true,
      packetization_mode: 1,
      profile_level_id: 0x42E01F
    }
  }
  @h265_codec %RTPCodecParameters{
    payload_type: 96,
    mime_type: "video/H265",
    clock_rate: @clock_rate,
    sdp_fmtp_line: %ExSDP.Attribute.FMTP{
      pt: 96,
      profile_id: 1
    }
  }

  def_input_pad :video, accepted_format: any_of(%H264{alignment: :au}, %H265{alignment: :au})

  def_options ice_servers: [spec: list()]

  @impl true
  def handle_init(_ctx, options) do
    stream_id = MediaStreamTrack.generate_stream_id()
    video_track = MediaStreamTrack.new(:video, [stream_id])

    state = %{
      ice_servers: options.ice_servers,
      video_codecs: [],
      peers: %{},
      peers_state: %{},
      payloader: nil,
      payloader_mod: nil,
      video_track: video_track
    }

    {[], state}
  end

  @impl true
  def handle_stream_format(:video, stream_format, ctx, state) do
    old_stream_format = ctx.pads.video.stream_format

    state =
      cond do
        is_nil(old_stream_format) ->
          init_rtp_payloader(stream_format, state)

        old_stream_format == stream_format ->
          state

        map_size(state.peers) == 0 ->
          init_rtp_payloader(stream_format, state)

        true ->
          raise "WebRTC doesn't support changing stream format"
      end

    {[], state}
  end

  @impl true
  def handle_parent_notification({:add_peer, peer_id}, _ctx, state) do
    {:ok, pc} =
      PeerConnection.start(
        ice_servers: state.ice_servers,
        video_codecs: state.video_codecs,
        audio_codecs: []
      )

    Process.monitor(peer_id)

    {:ok, _} = PeerConnection.add_track(pc, state.video_track)
    create_offer(pc, peer_id)

    {[],
     %{
       state
       | peers: Map.put(state.peers, pc, peer_id),
         peers_state: Map.put(state.peers_state, pc, :init)
     }}
  end

  @impl true
  def handle_parent_notification(peer_message, _ctx, state) do
    handle_peer_message(peer_message, state)
    {[], state}
  end

  @impl true
  def handle_buffer(:video, _buffer, _ctx, %{peers: peers} = state) when map_size(peers) == 0 do
    {[], state}
  end

  @impl true
  def handle_buffer(:video, buffer, _ctx, state) do
    timestamp =
      buffer.pts
      |> Time.divide_by_timebase(Ratio.new(Time.second(), @clock_rate))
      |> rem(@max_rtp_timestamp)

    {rtp_packets, payloader} =
      state.payloader_mod.handle_sample(buffer.payload, timestamp, state.payloader)

    Enum.each(rtp_packets, &send_video_packet(state, &1))

    {[], %{state | payloader: payloader}}
  end

  @impl true
  def handle_event(:video, %StreamClosed{}, _ctx, state) do
    Map.keys(state.peers) |> Enum.each(&PeerConnection.close/1)
    {[], %{state | peers: %{}, peers_state: %{}}}
  end

  @impl true
  def handle_event(:video, _event, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:ice_candidate, candidate}}, _ctx, state) do
    send(state.peers[pc], {:ice_candidate, ExWebRTC.ICECandidate.to_json(candidate)})
    {[], state}
  end

  @impl true
  def handle_info({:ex_webrtc, _pc, {:rtcp, _rtcp_packets}}, _ctx, state) do
    # ignore rtcp packets
    {[], state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:connection_state_change, conn_state}}, _ctx, state) do
    state =
      case conn_state do
        :connected ->
          %{state | peers_state: Map.put(state.peers_state, pc, :connected)}

        :failed ->
          PeerConnection.close(pc)

          %{
            state
            | peers: Map.delete(state.peers, pc),
              peers_state: Map.delete(state.peers_state, pc)
          }

        _other ->
          state
      end

    {[], state}
  end

  @impl true
  def handle_info({:DOWN, _monitor, :process, peer, _reason}, _ctx, state) do
    pc =
      case find_peer_pc(state.peers, peer) do
        nil ->
          peer

        pc ->
          PeerConnection.close(pc)
          pc
      end

    {[],
     %{
       state
       | peers: Map.delete(state.peers, pc),
         peers_state: Map.delete(state.peers_state, pc)
     }}
  end

  @impl true
  def handle_info(_message, _ctx, state) do
    {[], state}
  end

  defp create_offer(pc, peer_id) do
    {:ok, offer} = PeerConnection.create_offer(pc)
    :ok = PeerConnection.set_local_description(pc, offer)

    send(peer_id, {:offer, SessionDescription.to_json(offer)})
  end

  defp handle_peer_message({:answer, peer_id, answer}, state) do
    pc = find_peer_pc(state.peers, peer_id)

    answer
    |> SessionDescription.from_json()
    |> then(&PeerConnection.set_remote_description(pc, &1))
  end

  defp handle_peer_message({:ice_candidate, peer_id, ice_candidate}, state) do
    pc = find_peer_pc(state.peers, peer_id)

    ice_candidate
    |> ExWebRTC.ICECandidate.from_json()
    |> then(&PeerConnection.add_ice_candidate(pc, &1))
  end

  defp send_video_packet(state, packet) do
    state.peers_state
    |> Stream.filter(&(elem(&1, 1) == :connected))
    |> Stream.map(&elem(&1, 0))
    |> Enum.each(&PeerConnection.send_rtp(&1, state.video_track.id, packet))
  end

  defp find_peer_pc(peers, peer_id) do
    peers
    |> Enum.find({nil, nil}, &(elem(&1, 1) == peer_id))
    |> elem(0)
  end

  defp init_rtp_payloader(%H264{}, state) do
    %{
      state
      | video_codecs: [@h264_codec],
        payloader: Encoder.H264.init([]),
        payloader_mod: Encoder.H264
    }
  end

  defp init_rtp_payloader(%H265{}, state) do
    %{
      state
      | video_codecs: [@h265_codec],
        payloader: Encoder.H265.init([]),
        payloader_mod: Encoder.H265
    }
  end
end
