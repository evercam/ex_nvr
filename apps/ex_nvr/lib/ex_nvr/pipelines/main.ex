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

  alias ExNVR.{Devices, Recordings, Utils}
  alias ExNVR.Model.Device
  alias ExNVR.Pipeline.{Output, Source}

  @type encoding :: :H264

  @event_prefix [:ex_nvr, :main_pipeline]

  defmodule State do
    @moduledoc false

    use Bunch.Access

    alias ExNVR.Media.Track
    alias ExNVR.Model.Device

    @default_segment_duration 60

    @typedoc """
    Pipeline state

    `device` - The device from where to pull the media streams
    `segment_duration` - The duration of each video chunk saved by the storage bin.
    `supervisor_pid` - The supervisor pid of this pipeline (needed to stop a pipeline)
    `live_snapshot_waiting_pids` - List of pid waiting for live snapshot request to be completed
    `video_tracks` - Tuple denoting the main stream and sub stream video tracks.
    """
    @type t :: %__MODULE__{
            device: Device.t(),
            segment_duration: non_neg_integer(),
            supervisor_pid: pid(),
            live_snapshot_waiting_pids: list(),
            rtc_engine: pid() | atom(),
            video_tracks: {Track.t(), Track.t()}
          }

    @enforce_keys [:device]

    defstruct @enforce_keys ++
                [
                  segment_duration: @default_segment_duration,
                  supervisor_pid: nil,
                  live_snapshot_waiting_pids: [],
                  rtc_engine: nil,
                  video_tracks: {nil, nil}
                ]
  end

  def start_link(options \\ []) do
    with {:ok, sup_pid, pid} = res <-
           Membrane.Pipeline.start_link(__MODULE__, options,
             name: Utils.pipeline_name(options[:device])
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

    Logger.metadata(device_id: device.id)
    Membrane.Logger.info("Starting main pipeline for device: #{device.id}")

    state = %State{
      device: device,
      segment_duration: options[:segment_duration] || 60,
      rtc_engine: options[:rtc_engine]
    }

    common_spec = [
      child(:hls_sink, %Output.HLS{
        location: Path.join(Utils.hls_dir(device.id), "live"),
        segment_name_prefix: "live"
      }),
      child(:snapshooter, ExNVR.Elements.SnapshotBin),
      child(:webrtc, %Output.WebRTC{stream_id: device.id})
    ]

    if device.type == :ip do
      {stream_uri, sub_stream_uri} = Device.streams(device)

      Membrane.Logger.info("""
      Start streaming for
      main stream: #{stream_uri}
      sub stream: #{sub_stream_uri}
      """)

      spec =
        common_spec ++
          build_main_stream_spec(state, stream_uri) ++
          if sub_stream_uri,
            do: build_sub_stream_spec(sub_stream_uri),
            else: []

      {[spec: spec], state}
    else
      location = Device.file_location(device)

      Membrane.Logger.info("""
      Start streaming for
      location: #{location}
      """)

      {[spec: common_spec ++ build_file_stream_spec(location)], state}
    end
  end

  @impl true
  def handle_setup(_ctx, state) do
    do_create_directories(state.device)

    # Set device state and make last active run inactive
    # may happens on application crash
    device_state = if state.device.type == :file, do: :recording, else: :failed
    Recordings.deactivate_runs(state.device)
    {[], maybe_update_device_and_report(state, device_state)}
  end

  defp do_create_directories(device) do
    unless File.exists?(Utils.recording_dir(device.id)) do
      File.mkdir!(Utils.recording_dir(device.id))
    end

    unless File.exists?(Utils.hls_dir(device.id)) do
      File.mkdir!(Utils.hls_dir(device.id))
    end
  end

  @impl true
  def handle_child_notification(
        {:new_track, ssrc, track},
        :rtsp_source,
        _ctx,
        %State{} = state
      ) do
    if track.encoding != :H264 do
      Membrane.Logger.error("""
      Video codec #{track.encoding} is not supported
      Supported codecs are: H264
      """)

      state = maybe_update_device_and_report(state, :stopped)
      {[terminate: :normal], state}
    else
      state = maybe_update_device_and_report(state, :recording)

      spec = [
        get_child(:rtsp_source)
        |> via_out(Pad.ref(:output, ssrc))
        |> via_in(Pad.ref(:input, make_ref()))
        |> get_child(:funnel),
        get_child(:video_tee)
        |> via_out(:copy)
        |> via_in(Pad.ref(:input, :main_stream), options: [media_track: track])
        |> get_child(:webrtc)
      ]

      video_tracks = put_elem(state.video_tracks, 0, track)
      {[spec: {spec, group: :main_stream}], %{state | video_tracks: video_tracks}}
    end
  end

  @impl true
  def handle_child_notification(
        {:new_track, ssrc, track},
        {:rtsp_source, :sub_stream},
        _ctx,
        %State{} = state
      ) do
    if track.encoding != :H264 do
      Membrane.Logger.error("SubStream: only H264 streams are supported now")
      {[remove_child: {:rtsp_source, :sub_stream}], state}
    else
      spec = [
        get_child({:rtsp_source, :sub_stream})
        |> via_out(Pad.ref(:output, ssrc))
        |> via_in(Pad.ref(:input, make_ref()))
        |> get_child({:funnel, :sub_stream})
      ]

      video_tracks = put_elem(state.video_tracks, 1, track)
      {[spec: spec], %{state | video_tracks: video_tracks}}
    end
  end

  @impl true
  def handle_child_notification({:snapshot, snapshot}, _element, _ctx, state) do
    state.live_snapshot_waiting_pids
    |> Enum.map(&{:reply_to, {&1, {:ok, snapshot}}})
    |> then(&{&1, %{state | live_snapshot_waiting_pids: []}})
  end

  @impl true
  def handle_child_notification(:no_sockets, :unix_socket, _ctx, state) do
    Membrane.Logger.info("All unix sockets are disconnected, remove unix socket bin element")
    {[remove_children: [:unix_socket]], state}
  end

  @impl true
  def handle_child_notification(_notification, _element, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_child_pad_removed(:rtsp_source, Pad.ref(:output, _ssrc), _ctx, state) do
    state = maybe_update_device_and_report(state, :failed)
    {[remove_link: {:webrtc, Pad.ref(:input, :main_stream)}], state}
  end

  @impl true
  def handle_child_pad_removed({:rtsp_source, :sub_stream}, Pad.ref(:output, _ssrc), _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_child_pad_removed(_child, _pad, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_info({:pipeline_supervisor, pid}, _ctx, state) do
    {[], %{state | supervisor_pid: pid}}
  end

  @impl true
  def handle_info({:new_socket, unix_socket}, ctx, state) do
    childs = Map.keys(ctx.children)
    notify_action = [notify_child: {:unix_socket, {:new_socket, unix_socket}}]

    if Enum.member?(childs, :unix_socket) do
      {notify_action, state}
    else
      {source, track} =
        if Enum.member?(childs, {:tee, :sub_stream}) do
          {get_child({:tee, :sub_stream}), elem(state.video_tracks, 1)}
        else
          {get_child(:video_tee), elem(state.video_tracks, 0)}
        end

      spec = [
        source
        |> via_out(:copy)
        |> child(:unix_socket, %ExNVR.Pipeline.Output.Socket{encoding: track.encoding})
      ]

      {[spec: spec] ++ notify_action, state}
    end
  end

  @impl true
  def handle_call(:pipeline_supervisor, _ctx, state) do
    {[reply: state.supervisor_pid], state}
  end

  @impl true
  def handle_call({:live_snapshot, image_format}, ctx, state) do
    case state.live_snapshot_waiting_pids do
      [] ->
        {[spec: link_live_snapshot_elements(image_format)],
         %{state | live_snapshot_waiting_pids: [ctx.from]}}

      pids ->
        {[], %{state | live_snapshot_waiting_pids: [ctx.from | pids]}}
    end
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
  def handle_terminate_request(_ctx, state) do
    :telemetry.execute(@event_prefix ++ [:terminate], %{system_time: System.system_time()}, %{
      device_id: state.device.id
    })

    {[terminate: :normal], state}
  end

  defp build_main_stream_spec(state, stream_uri) do
    [
      child(:rtsp_source, %Source.RTSP{stream_uri: stream_uri}),
      child(:funnel, %Membrane.Funnel{end_of_stream: :never})
      |> child(:video_tee, Membrane.Tee.Master)
      |> via_out(:master)
      |> child({:storage_bin, :main_stream}, %Output.Storage{
        device_id: state.device.id,
        directory: Utils.recording_dir(state.device.id),
        target_segment_duration: state.segment_duration,
        correct_timestamp: true
      }),
      get_child(:video_tee)
      |> via_out(:copy)
      |> via_in(Pad.ref(:video, :main_stream))
      |> get_child(:hls_sink),
      get_child(:video_tee)
      |> via_out(:copy)
      |> child({:cvs_bufferer, :main_stream}, ExNVR.Elements.CVSBufferer)
    ]
  end

  defp build_file_stream_spec(location) do
    [
      child(:source, %Source.File{
        location: location
      })
      |> via_out(:video)
      |> child(:video_tee, Membrane.Tee.Master)
      |> via_out(:master)
      |> via_in(Pad.ref(:video, :main_stream))
      |> get_child(:hls_sink),
      get_child(:video_tee)
      |> via_out(:copy)
      |> child({:cvs_bufferer, :main_stream}, ExNVR.Elements.CVSBufferer)
    ]
  end

  defp build_sub_stream_spec(sub_stream_uri) do
    [
      child({:rtsp_source, :sub_stream}, %Source.RTSP{stream_uri: sub_stream_uri}),
      child({:funnel, :sub_stream}, %Membrane.Funnel{end_of_stream: :never})
      |> child({:tee, :sub_stream}, Membrane.Tee.Master)
      |> via_out(:master)
      |> via_in(Pad.ref(:video, :sub_stream))
      |> get_child(:hls_sink)
    ]
  end

  defp link_live_snapshot_elements(image_format) do
    ref = make_ref()

    [
      get_child({:cvs_bufferer, :main_stream})
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
  defp pipeline_pid(device), do: Process.whereis(Utils.pipeline_name(device))

  def child_spec(arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [arg]},
      restart: :transient,
      type: :supervisor
    }
  end
end
