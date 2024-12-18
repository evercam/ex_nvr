defmodule ExNVR.Pipeline.Source.RTSP do
  @moduledoc """
  RTSP pipeline source
  """

  use Membrane.Bin

  alias ExNVR.Model.Device
  alias ExNVR.Pipeline.Track

  @base_back_off_in_ms 10
  @max_back_off_in_ms :timer.minutes(2)

  def_output_pad :main_stream_output, accepted_format: _any, availability: :on_request
  def_output_pad :sub_stream_output, accepted_format: _any, availability: :on_request

  def_options device: [
                spec: Device.t(),
                description: "The device struct"
              ]

  @impl true
  def handle_init(_ctx, options) do
    {main_stream_uri, sub_stream_uri} = Device.streams(options.device)

    Membrane.Logger.info("""
    Start streaming for
    main stream: #{main_stream_uri}
    sub stream: #{sub_stream_uri}
    """)

    state = %{
      device: options.device,
      main_stream_uri: main_stream_uri,
      sub_stream_uri: sub_stream_uri,
      main_stream_reconnect_attempt: 0,
      sub_stream_reconnect_attempt: 0
    }

    {[], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    {[
       spec:
         rtsp_spec(:main_stream, state.main_stream_uri) ++
           rtsp_spec(:sub_stream, state.sub_stream_uri)
     ], state}
  end

  @impl true
  def handle_child_notification({:new_track, ssrc, track}, :main_stream, _ctx, state) do
    track = Track.new(track.type, track.rtpmap.encoding)
    state = %{state | main_stream_reconnect_attempt: 0}
    {[notify_parent: {:main_stream, ssrc, track}], state}
  end

  @impl true
  def handle_child_notification({:new_track, ssrc, track}, :sub_stream, _ctx, state) do
    track = Track.new(track.type, track.rtpmap.encoding)
    state = %{state | sub_stream_reconnect_attempt: 0}
    {[notify_parent: {:sub_stream, ssrc, track}], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:main_stream_output, ssrc) = ref, _ctx, state) do
    {[spec: [link_pads(:main_stream, ssrc, ref)]], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:sub_stream_output, ssrc) = ref, _ctx, state) do
    {[spec: [link_pads(:sub_stream, ssrc, ref)]], state}
  end

  @impl true
  def handle_crash_group_down(group_name, ctx, state) do
    {child_name, reconnect_attempt} =
      case group_name do
        :main_stream_group -> {:main_stream, state.main_stream_reconnect_attempt}
        :sub_stream_group -> {:sub_stream, state.sub_stream_reconnect_attempt}
      end

    actions = reconnect(reconnect_attempt, child_name, ctx)

    case child_name do
      :main_stream -> {actions, %{state | main_stream_reconnect_attempt: reconnect_attempt + 1}}
      :sub_stream -> {actions, %{state | sub_stream_reconnect_attempt: reconnect_attempt + 1}}
    end
  end

  @impl true
  def handle_tick({:reconnect, child_name}, _ctx, state) do
    uri =
      case child_name do
        :main_stream -> state.main_stream_uri
        :sub_stream -> state.sub_stream_uri
      end

    {[stop_timer: {:reconnect, child_name}, spec: rtsp_spec(child_name, uri)], state}
  end

  defp rtsp_spec(_name, nil), do: []

  defp rtsp_spec(name, uri) do
    [
      {child(name, %ExNVR.RTSP.Source{
         stream_uri: uri,
         allowed_media_types: [:video]
       }), group: :"#{name}_group", crash_group_mode: :temporary}
    ]
  end

  defp link_pads(child_name, ssrc, pad) do
    get_child(child_name)
    |> via_out(Pad.ref(:output, ssrc))
    |> bin_output(pad)
  end

  defp reconnect(reconnect_attempt, stream_type, ctx) do
    delay = calculate_retry_delay(reconnect_attempt)

    Membrane.Logger.error("""
    Error while connecting to #{stream_type}, retrying in #{delay} ms
    Reason: #{inspect(ctx.crash_reason)}
    """)

    actions = [start_timer: {{:reconnect, stream_type}, Membrane.Time.milliseconds(delay)}]

    if reconnect_attempt == 0 do
      # notify parent
      actions ++ [notify_parent: {:connection_lost, stream_type}]
    else
      actions
    end
  end

  defp calculate_retry_delay(reconnect_attempt) do
    :math.pow(2, reconnect_attempt)
    |> Kernel.*(@base_back_off_in_ms)
    |> min(@max_back_off_in_ms)
    |> trunc()
  end
end
