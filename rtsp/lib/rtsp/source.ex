defmodule ExNVR.RTSP.Source do
  @moduledoc false

  use Membrane.Source

  require Membrane.Logger

  import __MODULE__.PacketSplitter

  alias ExNVR.RTSP.OnvifMetadata
  alias ExNVR.RTSP.Parser
  alias ExNVR.RTSP.Source.{ConnectionManager, StreamHandler}
  alias Membrane.{H264, H265, Time}

  @initial_recv_buffer 1_000_000

  def_options stream_uri: [
                spec: binary(),
                description: "The RTSP uri of the resource to stream."
              ],
              allowed_media_types: [
                spec: [:video | :audio | :application],
                default: [:video, :audio, :application],
                description: """
                The media type to accept from the RTSP server.
                """
              ],
              timeout: [
                spec: non_neg_integer(),
                default: Time.seconds(15),
                description: "Set RTSP response timeout"
              ],
              keep_alive_interval: [
                spec: non_neg_integer(),
                default: Time.seconds(15),
                description: """
                Send a heartbeat to the RTSP server at a regular interval to
                keep the session alive.
                """
              ],
              onvif_replay: [
                spec: boolean(),
                default: false,
                description: "The stream uri is an onvif replay"
              ],
              start_date: [
                spec: DateTime.t(),
                default: nil,
                description: "The start date of the footage to replay"
              ],
              end_date: [
                spec: DateTime.t(),
                default: nil,
                description: "The end date of the footage to replay"
              ]

  def_output_pad :output,
    accepted_format: any_of(H264, H265, OnvifMetadata),
    flow_control: :push,
    availability: :on_request

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            stream_uri: binary(),
            allowed_media_types: ConnectionManager.media_types(),
            transport: Source.transport(),
            timeout: Time.t(),
            keep_alive_interval: Time.t(),
            tracks: [ConnectionManager.track()],
            rtsp_session: Membrane.RTSP.t() | nil,
            keep_alive_timer: reference() | nil,
            socket: :inet.socket() | nil,
            unprocessed_data: <<>>,
            onvif_replay: boolean(),
            start_date: DateTime.t(),
            end_date: DateTime.t()
          }

    @enforce_keys [:stream_uri, :allowed_media_types, :timeout, :keep_alive_interval]
    defstruct @enforce_keys ++
                [
                  socket: nil,
                  transport: :tcp,
                  tracks: [],
                  rtsp_session: nil,
                  keep_alive_timer: nil,
                  unprocessed_data: <<>>,
                  stream_handlers: %{},
                  onvif_replay: false,
                  start_date: nil,
                  end_date: nil
                ]
  end

  @impl true
  def handle_init(_ctx, options) do
    Process.set_label(:rtsp_source)
    state = struct(State, Map.from_struct(options))
    {[], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    state = ConnectionManager.establish_connection(state)
    {:tcp, socket} = List.first(state.tracks).transport
    {[start_timer: {:check_recbuf, Time.seconds(10)}], %{state | socket: socket}}
  end

  @impl true
  def handle_playing(_ctx, state) do
    Process.send_after(self(), :recv, 0)

    state = ConnectionManager.play(state)
    :ok = Membrane.RTSP.transfer_socket_control(state.rtsp_session, self())
    :ok = :inet.setopts(state.socket, buffer: @initial_recv_buffer, active: false)

    {[], state}
  end

  @impl true
  def handle_tick(:check_recbuf, _ctx, state) do
    with {:ok, [recbuf: recbuf]} <- :inet.getopts(state.socket, [:recbuf]) do
      :ok = :inet.setopts(state.socket, buffer: recbuf)
    end

    {[], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, ssrc), _ctx, state) do
    stream_handler = Map.get(state.stream_handlers, ssrc)
    actions = Enum.reverse(stream_handler.buffered_actions) |> List.flatten()

    stream_handlers = Map.update!(state.stream_handlers, ssrc, &%{&1 | buffered_actions: []})
    {actions, %{state | stream_handlers: stream_handlers}}
  end

  @impl true
  def handle_info(:recv, ctx, state) do
    Membrane.Logger.debug("Receiving data from socket")

    case :gen_tcp.recv(state.socket, 0, Time.as_milliseconds(state.timeout, :round)) do
      {:ok, message} ->
        datetime = DateTime.utc_now()

        {rtp_packets, _rtcp_packets, unprocessed_data} =
          split_packets(state.unprocessed_data <> message, state.rtsp_session, {[], []})

        {actions, stream_handlers} =
          rtp_packets
          |> Stream.map(&decode_rtp!/1)
          |> Stream.map(&decode_onvif_replay_extension/1)
          |> Enum.flat_map_reduce(state.stream_handlers, fn rtp_packet, handlers ->
            {notifcation_action, handlers} =
              maybe_init_stream_handler(state, handlers, rtp_packet)

            ssrc = rtp_packet.ssrc

            datetime =
              case state do
                %State{onvif_replay: true} ->
                  rtp_packet.extensions && rtp_packet.extensions.timestamp

                _state ->
                  datetime
              end

            {buffers, handler} = StreamHandler.handle_packet(handlers[ssrc], rtp_packet, datetime)

            {actions, handler} =
              buffers
              |> map_buffers_into_actions(ssrc)
              |> maybe_buffer_actions(handler, ssrc, ctx)

            {notifcation_action ++ actions, Map.put(handlers, ssrc, handler)}
          end)

        Process.send_after(self(), :recv, 5)
        {actions, %{state | stream_handlers: stream_handlers, unprocessed_data: unprocessed_data}}

      {:error, reason} ->
        raise "cannot read data from socket: #{inspect(reason)}"
    end
  end

  @impl true
  def handle_info(:keep_alive, _ctx, state) do
    pid = self()
    Task.start(fn -> ConnectionManager.keep_alive(state, pid) end)
    {[], state}
  end

  @impl true
  def handle_info(_message, _ctx, state) do
    {[], state}
  end

  defp decode_rtp!(packet) do
    case ExRTP.Packet.decode(packet) do
      {:ok, packet} ->
        packet

      _error ->
        raise """
        invalid rtp packet
        #{inspect(packet, limit: :infinity)}
        """
    end
  end

  defp decode_onvif_replay_extension(%ExRTP.Packet{extension_profile: 0xABAC} = packet) do
    extension = ExNVR.RTSP.OnvifReplayExtension.decode(packet.extensions)
    %{packet | extensions: extension}
  end

  defp decode_onvif_replay_extension(packet), do: packet

  defp maybe_init_stream_handler(_state, handlers, %{ssrc: ssrc}) when is_map_key(handlers, ssrc),
    do: {[], handlers}

  defp maybe_init_stream_handler(state, handlers, packet) do
    %{rtpmap: rtpmap, fmtp: fmtp} =
      track = Enum.find(state.tracks, &(&1.rtpmap.payload_type == packet.payload_type))

    encoding = String.to_atom(rtpmap.encoding)
    {parser_mod, parser_state} = parser(encoding, fmtp)

    stream_handler = %StreamHandler{
      clock_rate: rtpmap.clock_rate,
      parser_mod: parser_mod,
      parser_state: parser_state
    }

    actions = [notify_parent: {:new_track, packet.ssrc, Map.delete(track, :transport)}]
    {actions, Map.put(handlers, packet.ssrc, stream_handler)}
  end

  defp parser(:H264, fmtp) do
    sps = fmtp.sprop_parameter_sets && fmtp.sprop_parameter_sets.sps
    pps = fmtp.sprop_parameter_sets && fmtp.sprop_parameter_sets.pps

    {Parser.H264, Parser.H264.init(sps: sps, pps: pps)}
  end

  defp parser(:H265, fmtp) do
    parser_state =
      Parser.H265.init(
        vpss: List.wrap(fmtp && fmtp.sprop_vps) |> Enum.map(&clean_parameter_set/1),
        spss: List.wrap(fmtp && fmtp.sprop_sps) |> Enum.map(&clean_parameter_set/1),
        ppss: List.wrap(fmtp && fmtp.sprop_pps) |> Enum.map(&clean_parameter_set/1)
      )

    {Parser.H265, parser_state}
  end

  defp parser(:"vnd.onvif.metadata", _fmtp) do
    parser_state = Parser.OnvifMetadata.init([])
    {Parser.OnvifMetadata, parser_state}
  end

  defp map_buffers_into_actions(buffers, ssrc) do
    Enum.map(buffers, fn
      %Membrane.Buffer{} = buffer ->
        {:buffer, {Pad.ref(:output, ssrc), buffer}}

      %Membrane.Event.Discontinuity{} = event ->
        {:event, {Pad.ref(:output, ssrc), event}}

      stream_format ->
        {:stream_format, {Pad.ref(:output, ssrc), stream_format}}
    end)
  end

  defp maybe_buffer_actions(actions, handler, ssrc, ctx) do
    if linked?(ssrc, ctx) do
      {actions, handler}
    else
      {[], Map.update!(handler, :buffered_actions, &[actions | &1])}
    end
  end

  defp linked?(ssrc, ctx), do: Map.has_key?(ctx.pads, Pad.ref(:output, ssrc))

  # An issue with one of Milesight camera where the parameter sets have
  # <<0, 0, 0, 1>> at the end
  defp clean_parameter_set(ps) do
    case :binary.part(ps, byte_size(ps), -4) do
      <<0, 0, 0, 1>> -> :binary.part(ps, 0, byte_size(ps) - 4)
      _other -> ps
    end
  end
end
