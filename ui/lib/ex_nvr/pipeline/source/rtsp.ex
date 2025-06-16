defmodule ExNVR.Pipeline.Source.RTSP do
  @moduledoc """
  RTSP pipeline source
  """

  use Membrane.Source

  alias ExNVR.Model.Device
  alias ExNVR.Pipeline.Track

  @base_back_off_in_ms 10
  @max_back_off_in_ms :timer.minutes(2)
  @timeout :timer.seconds(10)

  def_output_pad :main_stream_output,
    accepted_format: _any,
    flow_control: :push,
    availability: :on_request

  def_output_pad :sub_stream_output,
    accepted_format: _any,
    flow_control: :push,
    availability: :on_request

  def_options device: [
                spec: Device.t(),
                description: "The device struct"
              ]

  defmodule Stream do
    @moduledoc false

    defstruct type: nil,
              stream_uri: nil,
              tracks: %{},
              pid: nil,
              all_pads_connected?: false,
              reconnect_attempt: 0,
              buffered_actions: []
  end

  @impl true
  def handle_init(_ctx, options) do
    {main_stream_uri, sub_stream_uri} = Device.streams(options.device)

    Membrane.Logger.info("""
    Start streaming for
    main stream: #{ExNVR.Utils.redact_url(main_stream_uri)}
    sub stream: #{ExNVR.Utils.redact_url(sub_stream_uri)}
    """)

    streams = %{
      main_stream: start_stream(main_stream_uri, :main_stream),
      sub_stream: start_stream(sub_stream_uri, :sub_stream)
    }

    {[], %{device: options.device, streams: streams}}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {main_actions, main_stream} = connect_stream(state.streams.main_stream)
    {sub_actions, sub_stream} = connect_stream(state.streams.sub_stream)

    {main_actions ++ sub_actions,
     %{state | streams: %{main_stream: main_stream, sub_stream: sub_stream}}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:main_stream_output, control_path), ctx, state) do
    do_handle_pad_added(:main_stream, control_path, ctx, state)
  end

  @impl true
  def handle_pad_added(Pad.ref(:sub_stream_output, control_path), ctx, state) do
    do_handle_pad_added(:sub_stream, control_path, ctx, state)
  end

  @impl true
  def handle_tick({:reconnect, stream_type}, _ctx, state) do
    {actions, stream} = connect_stream(state.streams[stream_type])
    state = put_in(state, [:streams, stream_type], stream)
    {[stop_timer: {:reconnect, stream_type}] ++ actions, state}
  end

  @impl true
  def handle_info(
        {stream_type, control_path, {sample, rtp_timestamp, keyframe?, timestamp}},
        _ctx,
        state
      ) do
    stream = state.streams[stream_type]
    track = Map.fetch!(stream.tracks, control_path)
    pad = pad_from_stream_type(stream_type, control_path)

    buffer = %Membrane.Buffer{
      payload: sample,
      dts: rtp_timestamp,
      pts: rtp_timestamp,
      metadata: %{
        :timestamp => timestamp,
        track.encoding => %{key_frame?: keyframe?}
      }
    }

    actions =
      if stream_format = get_stream_format(track.encoding, sample, keyframe?),
        do: [stream_format: {pad, stream_format}],
        else: []

    actions = actions ++ [buffer: {pad, buffer}]

    if stream.all_pads_connected? do
      {actions, state}
    else
      state =
        update_in(state, [:streams, stream_type], fn stream ->
          %{stream | buffered_actions: [actions | stream.buffered_actions]}
        end)

      {[], state}
    end
  end

  @impl true
  def handle_info({stream_type, :discontinuity}, _ctx, state) do
    stream = state.streams[stream_type]

    actions =
      Enum.map(stream.tracks, fn {control_path, _track} ->
        {:event,
         {pad_from_stream_type(stream_type, control_path), %Membrane.Event.Discontinuity{}}}
      end)

    {actions, state}
  end

  @impl true
  def handle_info({stream_type, :session_closed}, _ctx, state) do
    stream = state.streams[stream_type]

    actions =
      Enum.map(stream.tracks, fn {control_path, _track} ->
        {:event,
         {pad_from_stream_type(stream_type, control_path), %ExNVR.Pipeline.Event.StreamClosed{}}}
      end)

    {reconnect_actions, stream} = reconnect(state.streams[stream_type], :session_closed)
    {actions ++ reconnect_actions, put_in(state, [:streams, stream_type], stream)}
  end

  @impl true
  def handle_info(msg, _ctx, state) do
    Membrane.Logger.warning("Received unexpected message: #{inspect(msg)}")
    {[], state}
  end

  defp do_handle_pad_added(stream_type, control_path, ctx, state) do
    stream = state.streams[stream_type]

    if not Map.has_key?(stream.tracks, control_path) do
      raise "Unknown control path: #{control_path}"
    end

    pad_name = if stream_type == :main_stream, do: :main_stream_output, else: :sub_stream_output

    connected_pads =
      Enum.count(ctx.pads, fn
        {Pad.ref(^pad_name, _control_path), _} -> true
        _other -> false
      end)

    stream = %{stream | all_pads_connected?: connected_pads == map_size(stream.tracks)}
    state = put_in(state, [:streams, stream_type], stream)

    if stream.all_pads_connected? do
      actions = Enum.reverse(stream.buffered_actions) |> List.flatten()
      {actions, state}
    else
      {[], state}
    end
  end

  defp start_stream(nil, _type), do: nil

  defp start_stream(stream_uri, type) do
    {:ok, pid} =
      RTSP.start_link(
        stream_uri: stream_uri,
        allowed_media_types: [:video],
        name: type,
        timeout: @timeout
      )

    %Stream{type: type, stream_uri: stream_uri, pid: pid}
  end

  defp connect_stream(nil), do: {[], nil}

  defp connect_stream(stream) do
    with {:ok, tracks} <- RTSP.connect(stream.pid, @timeout + 1000),
         :ok <- RTSP.play(stream.pid, @timeout + 1000) do
      # Add sanity check: make sure that the tracks and their control path are the same between disconnection
      tracks = Map.new(tracks, &{&1.control_path, Track.new(&1.type, &1.rtpmap.encoding)})
      stream = %{stream | reconnect_attempt: 0, tracks: tracks}
      {[notify_parent: {stream.type, tracks}], stream}
    else
      {:error, reason} ->
        reconnect(stream, reason)
    end
  end

  defp reconnect(stream, reason) do
    delay = calculate_retry_delay(stream.reconnect_attempt)

    Membrane.Logger.error("""
    Error while connecting to #{stream.type}, retrying in #{delay} ms
    Reason: #{inspect(reason)}
    """)

    actions = [start_timer: {{:reconnect, stream.type}, Membrane.Time.milliseconds(delay)}]
    stream = %{stream | reconnect_attempt: stream.reconnect_attempt + 1}

    if stream.reconnect_attempt == 0 do
      {actions ++ [notify_parent: {:connection_lost, stream.type}], stream}
    else
      {actions, stream}
    end
  end

  defp calculate_retry_delay(reconnect_attempt) do
    :math.pow(2, reconnect_attempt)
    |> Kernel.*(@base_back_off_in_ms)
    |> min(@max_back_off_in_ms)
    |> trunc()
  end

  defp get_stream_format(_codec, _sample, false), do: nil

  defp get_stream_format(:h265, sample, true) do
    sps_nalu =
      sample
      |> MediaCodecs.H265.nalus()
      |> Enum.filter(&(MediaCodecs.H265.nalu_type(&1) == :sps))
      |> List.first()
      |> MediaCodecs.H265.parse_nalu()

    %Membrane.H265{
      alignment: :au,
      stream_structure: :annexb,
      width: MediaCodecs.H265.SPS.width(sps_nalu.content),
      height: MediaCodecs.H265.SPS.height(sps_nalu.content),
      profile: MediaCodecs.H265.SPS.profile(sps_nalu.content)
    }
  end

  defp get_stream_format(:h264, sample, true) do
    sps_nalu =
      sample
      |> MediaCodecs.H264.nalus()
      |> Enum.filter(&(MediaCodecs.H264.nalu_type(&1) == :sps))
      |> List.first()
      |> MediaCodecs.H264.parse_nalu()

    %Membrane.H264{
      alignment: :au,
      stream_structure: :annexb,
      width: MediaCodecs.H264.SPS.width(sps_nalu.content),
      height: MediaCodecs.H264.SPS.height(sps_nalu.content),
      profile: MediaCodecs.H264.SPS.profile(sps_nalu.content)
    }
  end

  defp pad_from_stream_type(:main_stream, ref), do: Pad.ref(:main_stream_output, ref)
  defp pad_from_stream_type(:sub_stream, ref), do: Pad.ref(:sub_stream_output, ref)
end
