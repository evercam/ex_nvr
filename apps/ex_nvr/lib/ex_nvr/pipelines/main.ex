defmodule ExNVR.Pipelines.Main do
  @moduledoc """
  Main pipeline that stream video footages and store them as chunks of configurable duration.

  ## Architecture
  The general architecture of the pipeline is as follows:
    * The pipeline starts first an element called `:rtsp_stream` which is responsible for connecting to the RTSP uri and
    streaming the media packets.
    * Once the pipeline receives a notification about an established session with RTSP server, the `RTP` session bin is
    linked to the output of the RTSP source
    * The new RTP stream is linked to a storage bin, which is responsible for chunking and storing the video footage, it emits a new
    notifcation to the parent each time a new segment starts/ends.

  In addition to the storage, this pipeline does additional tasks:
    * Creating HLS playlists from the main/sub stream
    * Capture live snapshots on request

  ## Limitations

  There's some limitation on the pipeline working, the pipeline supports:
    * Only video streams
    * Only H264 encoded streams

  ## Telemetry

  The pipeline emits the following `:telemetry` events:
    * `[:ex_nvr, :main_pipeline, :state]` - event emitted when the state of the device is updated.
    The event has no measurements and has the following metadata:
      * `device_id` - The id of the device to which this pipeline is attached
      * `old_state` - The old state of the device, (see `ExNVR.Model.Device.state()`)
      * `new_state` - The new state of the device, (see `ExNVR.Model.Device.state()`)

    * `[:ex_nvr, :main_pipeline, :terminate]` - event emitted when the pipeline is about to be terminated.
    The event has `system_time` as the measurement and has the following metadata:
      * `device_id` - The id of the device to which this pipeline is attached
  """

  use Membrane.Pipeline

  require Membrane.Logger

  alias ExNVR.Elements.RTSP.Source
  alias ExNVR.{Devices, Recordings, Utils}
  alias ExNVR.Model.Device
  alias Membrane.RTP.SessionBin

  @event_prefix [:ex_nvr, :main_pipeline]

  defmodule State do
    @moduledoc false

    use Bunch.Access

    alias ExNVR.Model.Device

    @default_segment_duration 60

    @typedoc """
    Pipeline state

    `device` - The device from where to pull the media streams
    `video_track` - Media description got from calling DESCRIBE method on the RTSP uri
    `sub_stream_video_track` - Media description of the sub stream got from calling DESCRIBE method on the RTSP uri
    `segment_duration` - The duration of each video chunk saved by the storage bin.
    `supervisor_pid` - The supervisor pid of this pipeline (needed to stop a pipeline)
    `live_snapshot_waiting_pids` - List of pid waiting for live snapshot request to be completed

    """
    @type t :: %__MODULE__{
            device: Device.t(),
            video_track: ExNVR.MediaTrack.t(),
            sub_stream_video_track: ExNVR.MediaTrack.t(),
            segment_duration: non_neg_integer(),
            supervisor_pid: pid(),
            live_snapshot_waiting_pids: list(),
            rtc_engine: pid() | atom()
          }

    @enforce_keys [:device]

    defstruct @enforce_keys ++
                [
                  segment_duration: @default_segment_duration,
                  video_track: nil,
                  sub_stream_video_track: nil,
                  supervisor_pid: nil,
                  live_snapshot_waiting_pids: [],
                  rtc_engine: nil
                ]
  end

  def start_link(options \\ []) do
    with {:ok, sup_pid, pid} = res <-
           Membrane.Pipeline.start_link(__MODULE__, options,
             name: pipeline_name(options[:device])
           ) do
      send(pid, {:pipeline_supervisor, sup_pid})
      res
    end
  end

  @spec supervisor(Device.t()) :: term()
  def supervisor(device) do
    Pipeline.call(pipeline_pid(device), :pipeline_supervisor)
  end

  @doc """
  Get a live snapshot
  """
  @spec live_snapshot(Device.t(), :jpeg | :png) :: term()
  def live_snapshot(device, image_format) do
    Pipeline.call(pipeline_pid(device), {:live_snapshot, image_format})
  end

  @spec media_track(Device.t(), :main_stream | :sub_stream) :: term()
  def media_track(device, stream \\ :main_stream) do
    Pipeline.call(pipeline_pid(device), {:media_track, stream})
  end

  def add_webrtc_peer(device, peer_id, channel_pid) do
    Pipeline.call(pipeline_pid(device), {:add_peer, {peer_id, channel_pid}})
  end

  def add_webrtc_media_event(device, peer_id, media_event) do
    Pipeline.call(pipeline_pid(device), {:media_event, peer_id, media_event})
  end

  # Pipeline callbacks

  @impl true
  def handle_init(_ctx, options) do
    device = options[:device]
    {stream_uri, sub_stream_uri} = Device.streams(device)

    Logger.metadata(device_id: device.id)
    Membrane.Logger.info("Starting main pipeline for device: #{device.id}")

    Membrane.Logger.info("""
    Start streaming for
    main stream: #{stream_uri}
    sub stream: #{sub_stream_uri}
    """)

    state = %State{
      device: device,
      segment_duration: options[:segment_duration] || 60,
      rtc_engine: options[:rtc_engine]
    }

    hls_sink = %ExNVR.Pipeline.Output.HLS{
      location: Path.join(Utils.hls_dir(device.id), "live"),
      segment_name_prefix: "live"
    }

    spec =
      [
        child(:rtsp_source, %Source{stream_uri: stream_uri}),
        {child(:hls_sink, hls_sink, get_if_exists: true), crash_group: {"hls", :temporary}},
        child(:snapshooter, ExNVR.Elements.SnapshotBin),
        child(:webrtc, %ExNVR.Pipeline.Output.WebRTC{stream_id: device.id})
      ] ++
        if sub_stream_uri,
          do: [child({:rtsp_source, :sub_stream}, %Source{stream_uri: sub_stream_uri})],
          else: []

    {[spec: spec], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    # Set the device to failed state and make last active run inactive
    # may happens on application crash
    Recordings.deactivate_runs(state.device)
    {[], maybe_update_device_and_report(state, :failed)}
  end

  @impl true
  def handle_child_notification({:connection_lost, _ref}, :rtsp_source, _ctx, state) do
    state = maybe_update_device_and_report(state, :failed)

    unlink_actions = [
      remove_link: {:webrtc, Pad.ref(:input, :main_stream)},
      remove_link: {:hls_sink, Pad.ref(:video, :main_stream)}
    ]

    {[remove_children: :main_stream] ++ unlink_actions, state}
  end

  @impl true
  def handle_child_notification({:connection_lost, _ref}, _elem, _ctx, state) do
    {[remove_child: :sub_stream, remove_link: {:hls_sink, Pad.ref(:video, :sub_stream)}], state}
  end

  @impl true
  def handle_child_notification(
        {:rtsp_setup_complete, video_track, ref},
        :rtsp_source,
        _ctx,
        %State{} = state
      ) do
    if video_track.codec != :H264 do
      Membrane.Logger.error("""
      Video codec #{video_track.codec} is not supported
      Supported codecs are: H264
      """)

      state = maybe_update_device_and_report(state, :stopped)
      {[terminate: :normal], state}
    else
      state = maybe_update_device_and_report(state, :recording)
      handle_rtsp_stream_setup(video_track, ref, state)
    end
  end

  @impl true
  def handle_child_notification(
        {:rtsp_setup_complete, video_track, ref},
        {:rtsp_source, :sub_stream},
        _ctx,
        %State{} = state
      ) do
    if video_track.codec != :H264 do
      Membrane.Logger.error("SubStream: only H264 streams are supported now")
      {[remove_child: {:rtsp_source, :sub_stream}], state}
    else
      handle_rtsp_sub_stream_setup(video_track, ref, state)
    end
  end

  @impl true
  def handle_child_notification(
        {:new_rtp_stream, ssrc, _pt, _extensions},
        {:rtp, ref},
        _ctx,
        state
      ) do
    spec = [
      get_child({:rtp, ref})
      |> via_out(Pad.ref(:output, ssrc), options: [depayloader: Membrane.RTP.H264.Depayloader])
      |> child({:rtp_parser, ref}, %Membrane.H264.Parser{framerate: {0, 0}})
      |> child(:video_tee, Membrane.Tee.Master)
      |> via_out(:master)
      |> child({:storage_bin, ref}, %ExNVR.Elements.StorageBin{
        device_id: state.device.id,
        target_segment_duration: state.segment_duration
      }),
      get_child(:video_tee)
      |> via_out(:copy)
      |> via_in(Pad.ref(:video, :main_stream))
      |> get_child(:hls_sink),
      get_child(:video_tee)
      |> via_out(:copy)
      |> child({:cvs_bufferer, ref}, ExNVR.Elements.CVSBufferer),
      get_child(:video_tee)
      |> via_out(:copy)
      |> via_in(Pad.ref(:input, :main_stream), options: [media_track: state.video_track])
      |> get_child(:webrtc)
    ]

    {[spec: {spec, group: :main_stream}], state}
  end

  @impl true
  def handle_child_notification(
        {:new_rtp_stream, ssrc, _pt, _extensions},
        {:rtp, :sub_stream, ref} = rtp_child,
        _ctx,
        state
      ) do
    spec = [
      get_child(rtp_child)
      |> via_out(Pad.ref(:output, ssrc), options: [depayloader: Membrane.RTP.H264.Depayloader])
      |> child({:rtp_parser, :sub_stream, ref}, %Membrane.H264.Parser{framerate: {0, 0}})
      |> via_in(Pad.ref(:video, :sub_stream))
      |> get_child(:hls_sink)
    ]

    {[spec: {spec, group: :sub_stream}], state}
  end

  @impl true
  def handle_child_notification({:snapshot, snapshot}, _element, _ctx, state) do
    state.live_snapshot_waiting_pids
    |> Enum.map(&{:reply_to, {&1, {:ok, snapshot}}})
    |> then(&{&1, %{state | live_snapshot_waiting_pids: []}})
  end

  @impl true
  def handle_child_notification(_notification, _element, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_crash_group_down(group, ctx, state) do
    Membrane.Logger.error("Group '#{group}' crashed")
    {[remove_children: ctx.members], state}
  end

  @impl true
  def handle_info({:pipeline_supervisor, pid}, _ctx, state) do
    {[], %{state | supervisor_pid: pid}}
  end

  @impl true
  def handle_call(:pipeline_supervisor, _ctx, state) do
    {[reply: state.supervisor_pid], state}
  end

  @impl true
  def handle_call({:live_snapshot, image_format}, ctx, state) do
    case state.live_snapshot_waiting_pids do
      [] ->
        {[spec: link_live_snapshot_elements(ctx, image_format)],
         %{state | live_snapshot_waiting_pids: [ctx.from]}}

      pids ->
        {[], %{state | live_snapshot_waiting_pids: [ctx.from | pids]}}
    end
  end

  @impl true
  def handle_call({:media_track, :main_stream}, _ctx, state) do
    {[reply: state.video_track], state}
  end

  @impl true
  def handle_call({:media_track, :sub_stream}, _ctx, state) do
    {[reply: state.sub_stream_video_track], state}
  end

  @impl true
  def handle_call({:add_peer, _peer} = message, _ctx, state) do
    case state.device.state do
      :recording ->
        {[reply: :ok, notify_child: {:webrtc, message}], state}

      _ ->
        {[reply: {:error, :offline}], state}
    end
  end

  @impl true
  def handle_call({:media_event, _peer_id, _media_event} = message, ctx, state) do
    {[reply: {ctx.from, :ok}, notify_child: {:webrtc, message}], state}
  end

  @impl true
  def handle_child_pad_removed(_child, _pad, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    :telemetry.execute(@event_prefix ++ [:terminate], %{system_time: System.system_time()}, %{
      device_id: state.device.id
    })

    {[], state}
  end

  defp handle_rtsp_stream_setup(%ExNVR.MediaTrack{} = video_track, ref, state) do
    fmt_mapping =
      Map.put(%{}, video_track.payload_type, {video_track.codec, video_track.clock_rate})

    spec = [
      get_child(:rtsp_source)
      |> via_out(Pad.ref(:output, ref))
      |> via_in(Pad.ref(:rtp_input, make_ref()))
      |> child({:rtp, ref}, %SessionBin{fmt_mapping: fmt_mapping})
    ]

    {[spec: spec], %State{state | video_track: video_track}}
  end

  defp handle_rtsp_sub_stream_setup(%ExNVR.MediaTrack{} = video_track, ref, state) do
    fmt_mapping =
      Map.put(%{}, video_track.payload_type, {video_track.codec, video_track.clock_rate})

    spec = [
      get_child({:rtsp_source, :sub_stream})
      |> via_out(Pad.ref(:output, ref))
      |> via_in(Pad.ref(:rtp_input, make_ref()))
      |> child({:rtp, :sub_stream, ref}, %SessionBin{fmt_mapping: fmt_mapping})
    ]

    {[spec: spec], %State{state | sub_stream_video_track: video_track}}
  end

  defp link_live_snapshot_elements(ctx, image_format) do
    ref = make_ref()

    cvs_bufferer =
      ctx.children
      |> Map.keys()
      |> Enum.find(&(is_tuple(&1) and elem(&1, 0) == :cvs_bufferer))

    [
      get_child(cvs_bufferer)
      |> via_out(Pad.ref(:output, ref))
      |> via_in(Pad.ref(:input, ref), options: [format: image_format])
      |> get_child(:snapshooter)
    ]
  end

  defp maybe_update_device_and_report(%{device: %{state: device_state}} = state, device_state),
    do: state

  defp maybe_update_device_and_report(%{device: device} = state, new_state) do
    {:ok, updated_device} = Devices.update_state(device, new_state)

    :telemetry.execute(@event_prefix ++ [:state], %{}, %{
      device_id: device.id,
      old_state: device.state,
      new_state: updated_device.state
    })

    %{state | device: updated_device}
  end

  # Pipeline process details

  defp pipeline_name(%{id: device_id}), do: :"pipeline_#{device_id}"

  defp pipeline_pid(device), do: Process.whereis(pipeline_name(device))

  def child_spec(arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [arg]},
      restart: :transient,
      type: :supervisor
    }
  end
end
