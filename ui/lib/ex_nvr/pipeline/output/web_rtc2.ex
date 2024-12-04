defmodule ExNVR.Pipeline.Output.WebRTC2 do
  @moduledoc """
  Send video/audio via WebRTC.
  """

  use Membrane.Sink

  require Membrane.Logger

  import Bitwise

  alias ExNVR.RTP.Payloader
  alias ExNVR.Pipeline.Event.StreamClosed
  alias ExWebRTC.{MediaStreamTrack, PeerConnection, RTPCodecParameters, SessionDescription}
  alias Membrane.{H264, H265, Time}

  @max_payload_size 1460
  @max_rtp_timestamp 1 <<< 32
  @max_rtp_seq_no (1 <<< 16) - 1

  @clock_rate 90_000
  @video_codecs [
    %RTPCodecParameters{payload_type: 96, mime_type: "video/H264", clock_rate: @clock_rate}
  ]

  def_input_pad :video, accepted_format: any_of(%H264{alignment: :au}, %H265{alignment: :au})

  def_options ice_servers: [
                spec: list(),
                default: [%{urls: "stun:stun.l.google.com:19302"}]
              ]

  @impl true
  def handle_init(_ctx, options) do
    stream_id = MediaStreamTrack.generate_stream_id()
    video_track = MediaStreamTrack.new(:video, [stream_id])

    state = %{
      ice_servers: options.ice_servers,
      peers: %{},
      peers_state: %{},
      next_sequence_number: Enum.random(0..@max_rtp_seq_no),
      payloader: Payloader.H264.new(@max_payload_size),
      video_track: video_track
    }

    {[], state}
  end

  @impl true
  def handle_parent_notification({:add_peer, peer_id}, _ctx, state) do
    {:ok, pc} =
      PeerConnection.start_link(
        ice_servers: state.ice_servers,
        video_codecs: @video_codecs,
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
  def handle_buffer(:video, _buffer, _ctx, %{peers: []} = state) do
    {[], state}
  end

  @impl true
  def handle_buffer(:video, buffer, _ctx, state) do
    {rtp_packets, payloader} = Payloader.H264.payload(state.payloader, buffer.payload)

    timestamp =
      buffer.pts
      |> Time.divide_by_timebase(Ratio.new(Time.second(), @clock_rate))
      |> rem(@max_rtp_timestamp)

    new_seq_number =
      Enum.reduce(rtp_packets, state.next_sequence_number, fn packet, seq ->
        packet = %{packet | sequence_number: seq, timestamp: timestamp}
        send_video_packet(state, packet)
        seq + 1 &&& @max_rtp_seq_no
      end)

    {[],
     %{
       state
       | payloader: payloader,
         next_sequence_number: new_seq_number
     }}
  end

  @impl true
  def handle_event(:video, %StreamClosed{}, _ctx, state) do
    Map.keys(state.peers) |> Enum.each(&PeerConnection.close/1)
    {[], %{state | peers: %{}, peers_state: %{}}}
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
  def handle_info({:ex_webrtc, pc, {:connection_state_change, :connected}}, _ctx, state) do
    {[], %{state | peers_state: Map.put(state.peers_state, pc, :connected)}}
  end

  @impl true
  def handle_info({:DOWN, _monitor, :process, peer_id, _reason}, _ctx, state) do
    if pc = find_peer_pc(state.peers, peer_id) do
      PeerConnection.close(pc)

      {[],
       %{
         state
         | peers: Map.delete(state.peers, pc),
           peers_state: Map.delete(state.peers_state, pc)
       }}
    else
      {[], state}
    end
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
    |> Enum.find(&(elem(&1, 1) == peer_id))
    |> elem(0)
  end
end
