defmodule ExNVR.Pipeline.Output.WebRTC do
  @moduledoc """
  An output element for a pipeline that converts video NAL units to
  a WebRTC track.

  The general architecture of the element is a little bit involving :
    * First this element will spawn a new RTC engine and create a stream endpoint
    * The stream endpoint is responsible for converting the video NAL units to an RTP packets
    suitable for sending via WebRTC
    * Once the bin input of this element is attached, we send a notification to the stream
    endpoint which publishes a new track into the engine
    * This element gets a `source_pid` of the source element of the stream endpoint.
    The stream endpoint source element will receive buffers sent via a Sink element
    created by this bin.
  """

  use Membrane.Bin

  require Membrane.Logger

  alias ExNVR.Pipeline.Output
  alias Membrane.{H264, H265}
  alias Membrane.ICE.TURNManager
  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Message
  alias Membrane.RTC.Engine.Endpoint.WebRTC

  def_input_pad :input,
    accepted_format: any_of(%H264{alignment: :au}, %H265{alignment: :au}),
    availability: :on_request,
    options: [
      encoding: [
        spec: :H264,
        description: "encoding of the media"
      ]
    ]

  def_options stream_id: [
                spec: binary(),
                description: "A stream id"
              ]

  @impl true
  def handle_init(_ctx, options) do
    turn_options = integrated_turn_options()

    network_options = [
      integrated_turn_options: turn_options,
      integrated_turn_domain: Application.fetch_env!(:ex_nvr, :integrated_turn_domain),
      dtls_pkey: Application.get_env(:ex_nvr, :dtls_pkey),
      dtls_cert: Application.get_env(:ex_nvr, :dtls_cert)
    ]

    turn_tcp_port = Application.fetch_env!(:ex_nvr, :integrated_turn_tcp_port)
    TURNManager.ensure_tcp_turn_launched(turn_options, port: turn_tcp_port)

    {:ok, rtc_engine} = Engine.start_link([id: options.stream_id], [])
    Engine.register(rtc_engine, self())

    stream_endpoint_id = UUID.uuid4()
    Engine.add_endpoint(rtc_engine, %Output.WebRTC.StreamEndpoint{}, id: stream_endpoint_id)

    {[],
     %{
       rtc_engine: rtc_engine,
       network_options: network_options,
       peer_channels: %{},
       stream_endpoint_id: stream_endpoint_id,
       encoding: nil
     }}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, :main_stream) = pad, ctx, state) do
    encoding = ctx.pad_options[:encoding]

    if encoding == :H264 do
      Engine.message_endpoint(
        state.rtc_engine,
        state.stream_endpoint_id,
        {:encoding, encoding}
      )
    end

    spec = [bin_input(pad) |> child(:sink, Output.WebRTC.Sink)]

    {[spec: spec], %{state | encoding: encoding}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, :sub_stream), _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_pad_removed(Pad.ref(:input, :main_stream), _ctx, state) do
    Engine.message_endpoint(state.rtc_engine, state.stream_endpoint_id, :remove_track)
    {[remove_children: :sink], %{state | encoding: nil}}
  end

  @impl true
  def handle_pad_removed(Pad.ref(:input, :sub_stream), _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_parent_notification(
        {:add_peer, {peer_id, channel_pid}},
        _ctx,
        %{rtc_engine: engine} = state
      ) do
    state = put_in(state, [:peer_channels, peer_id], channel_pid)
    Process.monitor(channel_pid)

    handshake_opts =
      if state.network_options[:dtls_key] && state.network_options[:dtls_cert] do
        [
          client_mode: false,
          dtls_srtp: true,
          pkey: state.network_options[:dtls_key],
          cert: state.network_options[:dtls_cert]
        ]
      else
        [
          client_mode: false,
          dtls_srtp: true
        ]
      end

    webrtc_endpoint = %WebRTC{
      rtc_engine: engine,
      direction: :recv,
      ice_name: peer_id,
      owner: self(),
      integrated_turn_options: state.network_options[:integrated_turn_options],
      handshake_opts: handshake_opts,
      webrtc_extensions: [Membrane.WebRTC.Extension.TWCC]
    }

    result = Engine.add_endpoint(engine, webrtc_endpoint, id: peer_id)
    {[notify_parent: {:add_peer, result}, notify_child: {:sink, {:stream, true}}], state}
  end

  @impl true
  def handle_parent_notification({:media_event, peer_id, media_event}, _ctx, state) do
    Engine.message_endpoint(state.rtc_engine, peer_id, {:media_event, media_event})
    {[], state}
  end

  @impl true
  def handle_parent_notification(_notification, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_info(
        %Message.EndpointMessage{
          endpoint_id: endpoint_id,
          message: {:media_event, media_event}
        },
        _ctx,
        state
      ) do
    channel_pid = state.peer_channels[endpoint_id]
    send(channel_pid, {:media_event, media_event})
    {[], state}
  end

  @impl true
  def handle_info(%Message.EndpointAdded{} = msg, _ctx, state) do
    Membrane.Logger.info(
      "new peer of type #{inspect(msg.endpoint_type)} joined with id '#{msg.endpoint_id}'"
    )

    {[], state}
  end

  @impl true
  def handle_info(%Message.EndpointRemoved{} = msg, _ctx, state) do
    Membrane.Logger.info("peer with id '#{msg.endpoint_id}' removed")
    {[], state}
  end

  @impl true
  def handle_info(
        %Message.EndpointMessage{endpoint_id: _, message: {:source_pid, source_pid}},
        _ctx,
        state
      ) do
    {[notify_child: {:sink, {:source_pid, source_pid}}], state}
  end

  @impl true
  def handle_info(
        %Message.EndpointCrashed{endpoint_id: endpoint_id},
        _ctx,
        %{stream_endpoint_id: endpoint_id} = state
      ) do
    Membrane.Logger.error("Stream endpoint #{endpoint_id} crashed")
    Engine.add_endpoint(state.rtc_engine, %Output.WebRTC.StreamEndpoint{}, id: endpoint_id)

    if state.media_track do
      Engine.message_endpoint(
        state.rtc_engine,
        endpoint_id,
        {:media_track, state.media_track}
      )
    end

    {[], state}
  end

  @impl true
  def handle_info(%Engine.Message.EndpointCrashed{endpoint_id: peer_id}, _ctx, state) do
    Membrane.Logger.error("Peer endpoint crashed #{peer_id}")
    {peer_channel, state} = pop_in(state, [:peer_channels, peer_id])

    if peer_channel do
      send(peer_channel, :endpoint_crashed)
    else
      Membrane.Logger.warning("""
      No peer corresponding to endpoint: #{peer_id}.
      It might have left just before the crash happend or the
      crash happend because of the peer leaving
      """)
    end

    maybe_stop_streaming(state)
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, channel_pid, _reason}, _ctx, state) do
    {peer_id, _peer_channel_pid} =
      Enum.find(state.peer_channels, fn {_peer_id, peer_channel_pid} ->
        peer_channel_pid == channel_pid
      end)

    Membrane.Logger.debug("Peer #{peer_id} left")

    Engine.remove_endpoint(state.rtc_engine, peer_id)
    {_elem, state} = pop_in(state, [:peer_channels, peer_id])

    maybe_stop_streaming(state)
  end

  @impl true
  def handle_info(message, _ctx, state) do
    Membrane.Logger.warning("Received unexpected message: #{inspect(message)}")
    {[], state}
  end

  defp integrated_turn_options() do
    turn_mock_ip = Application.fetch_env!(:ex_nvr, :integrated_turn_ip)

    turn_ip =
      if Application.fetch_env!(:ex_nvr, :env) == :prod, do: {0, 0, 0, 0}, else: turn_mock_ip

    turn_cert_file =
      case Application.fetch_env(:ex_nvr, :integrated_turn_cert_pkey) do
        {:ok, val} -> val
        :error -> nil
      end

    [
      ip: turn_ip,
      mock_ip: turn_mock_ip,
      ports_range: Application.fetch_env!(:ex_nvr, :integrated_turn_port_range),
      cert_file: turn_cert_file
    ]
  end

  defp maybe_stop_streaming(state) do
    if state.peer_channels == %{} do
      {[notify_child: {:sink, {:stream, false}}], state}
    else
      {[], state}
    end
  end
end
