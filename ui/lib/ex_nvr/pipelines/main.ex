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
    * Only H264/H265 encoded streams

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

  alias __MODULE__.State
  alias ExNVR.{Devices, Recordings, Utils}
  alias ExNVR.Elements.VideoStreamStatReporter
  alias ExNVR.Model.Device
  alias ExNVR.Pipeline.{Output, Source, StorageMonitor}

  @type encoding :: :H264 | :H265

  @event_prefix [:ex_nvr, :main_pipeline]
  @default_segment_duration Membrane.Time.seconds(60)
  @default_ice_servers [%{urls: "stun:stun.l.google.com:19302"}]

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

  @spec add_webrtc_peer(Device.t(), :low | :high) :: :ok | {:error, any()}
  def add_webrtc_peer(device, stream_type) do
    Pipeline.call(pipeline_pid(device), {:add_peer, stream_type, self()})
  end

  @spec forward_peer_message(Device.t(), :low | :high, tuple()) :: :ok
  def forward_peer_message(device, stream_type, {message_type, data}) do
    Pipeline.call(
      pipeline_pid(device),
      {:peer_message, stream_type, {message_type, self(), data}}
    )
  end

  @spec get_tracks(Device.t()) :: %{atom() => [ExNVR.Pipeline.Track]}
  def get_tracks(device) do
    Pipeline.call(pipeline_pid(device), :tracks)
  end

  # manually start and stop recording
  # if recording stopped with this functions
  # it'll remain on that state until start_recording is called.
  def start_recording(device) do
    Pipeline.call(pipeline_pid(device), {:record?, true})
  end

  def stop_recording(device) do
    Pipeline.call(pipeline_pid(device), {:record?, false})
  end

  # Pipeline callbacks
  @impl true
  def handle_init(_ctx, options) do
    device = options[:device]

    Logger.metadata(device_id: device.id)
    Membrane.Logger.info("Starting main pipeline for device: #{device.id}")

    ice_servers =
      case ice_servers() do
        {:ok, []} ->
          @default_ice_servers

        {:ok, servers} ->
          servers

        {:error, _error} ->
          Membrane.Logger.warning("Invalid ice servers, using defaults")
          @default_ice_servers
      end

    state = %State{
      device: device,
      segment_duration: options[:segment_duration] || @default_segment_duration,
      ice_servers: ice_servers
    }

    {[], state}
  end

  @impl true
  def handle_setup(_ctx, %{device: device} = state) do
    spec =
      [
        child(:hls_sink, %Output.HLS{
          location: Path.join(Utils.hls_dir(device.id), "live")
        })
      ] ++ build_device_spec(device, state)

    {:ok, pid} = StorageMonitor.start_link(device: device)
    state = %{state | storage_monitor: pid}

    # Set device state and make last active run inactive
    # may happens on application crash
    device_state = if state.device.type == :file, do: :streaming, else: :failed
    Recordings.deactivate_runs(state.device)
    {[spec: spec], maybe_update_device_and_report(state, device_state)}
  end

  @impl true
  def handle_child_notification({:main_stream, tracks}, child_name, _ctx, state) do
    [{id, track}] = Map.to_list(tracks)
    state = maybe_update_device_and_report(state, :streaming)
    old_track = state.main_stream_video_track

    spec =
      if is_nil(old_track) do
        [
          get_child(child_name)
          |> via_out(Pad.ref(:main_stream_output, id))
          |> child(:tee, Membrane.Tee)
        ] ++
          build_main_stream_spec(state)
      else
        []
      end

    {[spec: spec], %{state | main_stream_video_track: track}}
  end

  @impl true
  def handle_child_notification({:sub_stream, tracks}, child_name, _ctx, state) do
    [{id, track}] = Map.to_list(tracks)
    old_track = state.sub_stream_video_track

    spec =
      if is_nil(old_track) do
        [
          get_child(child_name)
          |> via_out(Pad.ref(:sub_stream_output, id))
          |> child({:tee, :sub_stream}, Membrane.Tee)
        ] ++ build_sub_stream_spec(state)
      else
        []
      end

    {[spec: spec], %{state | sub_stream_video_track: track}}
  end

  @impl true
  def handle_child_notification({:connection_lost, :main_stream}, :rtsp_source, _ctx, state) do
    {[], maybe_update_device_and_report(state, :failed)}
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
  def handle_child_notification(:new_segment, {:storage, :main_stream}, _ctx, state) do
    {[], maybe_update_device_and_report(state, :recording)}
  end

  @impl true
  def handle_child_notification({:stats, stats}, {:stats_reporter, :main_stream}, _ctx, state) do
    track = state.main_stream_video_track
    {[], %State{state | main_stream_video_track: %{track | stats: stats}}}
  end

  @impl true
  def handle_child_notification({:stats, stats}, {:stats_reporter, :sub_stream}, _ctx, state) do
    track = state.sub_stream_video_track
    {[], %State{state | sub_stream_video_track: %{track | stats: stats}}}
  end

  @impl true
  def handle_child_notification(_notification, _element, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_child_pad_removed(_child, _pad, _ctx, state) do
    # rtsp source will delete its own pads. no need to
    # do anything since a connection lost notification is sent to the parent
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
      source = childs |> Enum.find(:tee, &(&1 == {:tee, :sub_stream})) |> get_child()

      spec = [
        source
        |> via_out(:push_output)
        |> child(:unix_socket, ExNVR.Pipeline.Output.Socket)
      ]

      {[spec: spec] ++ notify_action, state}
    end
  end

  @impl true
  def handle_info({:storage_monitor, :record?, false}, ctx, state) do
    Membrane.Logger.info("[StorageMonitor] stop recording")

    childs_to_delete = [
      {:thumbnailer, :sub_stream},
      {:storage, :sub_stream},
      {:storage, :main_stream}
    ]

    state = %{maybe_update_device_and_report(state, :streaming) | record_main_stream?: false}

    actions =
      Map.keys(ctx.children)
      |> Enum.filter(&Enum.member?(childs_to_delete, &1))
      |> then(&[remove_children: &1])

    {actions, state}
  end

  @impl true
  def handle_info({:storage_monitor, :record?, true}, _ctx, state) do
    Membrane.Logger.info("[StorageMonitor] start recording")
    state = %{state | record_main_stream?: state.device.type != :file}

    main_stream_spec = build_main_stream_storage_spec(state)

    sub_stream_spec =
      build_sub_stream_storage_spec(state.device) ++ build_sub_stream_bif_spec(state)

    case {state.main_stream_video_track, state.sub_stream_video_track} do
      {nil, nil} ->
        {[], state}

      {nil, _sub_stream} ->
        {[spec: sub_stream_spec], state}

      {_main_stream, nil} ->
        {[spec: main_stream_spec], state}

      {_main_stream, _sub_stream} ->
        {[spec: main_stream_spec ++ sub_stream_spec], state}
    end
  end

  @impl true
  def handle_call(:pipeline_supervisor, _ctx, state) do
    {[reply: state.supervisor_pid], state}
  end

  @impl true
  def handle_call({:live_snapshot, _image_format}, ctx, state) do
    case state.live_snapshot_waiting_pids do
      [] ->
        {[notify_child: {{:snapshooter, :main_stream}, :snapshot}],
         %{state | live_snapshot_waiting_pids: [ctx.from]}}

      pids ->
        {[], %{state | live_snapshot_waiting_pids: [ctx.from | pids]}}
    end
  end

  @impl true
  def handle_call({:add_peer, :high, peer}, _ctx, state) do
    track = state.main_stream_video_track

    case can_add_webrtc_peer(state.device, track) do
      :ok -> {[reply: :ok, notify_child: {:webrtc, {:add_peer, peer}}], state}
      error -> {[reply: error], state}
    end
  end

  @impl true
  def handle_call({:add_peer, :low, peer}, _ctx, state) do
    track = state.sub_stream_video_track

    case can_add_webrtc_peer(state.device, track) do
      :ok -> {[reply: :ok, notify_child: {{:webrtc, :sub_stream}, {:add_peer, peer}}], state}
      error -> {[reply: error], state}
    end
  end

  @impl true
  def handle_call({:peer_message, stream_type, message}, _ctx, state) do
    child =
      case stream_type do
        :high -> :webrtc
        :low -> {:webrtc, :sub_stream}
      end

    {[reply: :ok, notify_child: {child, message}], state}
  end

  @impl true
  def handle_call(:tracks, _ctx, state) do
    tracks =
      [{:main_stream, state.main_stream_video_track}, {:sub_stream, state.sub_stream_video_track}]
      |> Enum.reject(&is_nil(elem(&1, 1)))
      |> Map.new()

    {[reply: tracks], state}
  end

  def handle_call({:record?, record?}, _ctx, state) do
    if record? do
      Membrane.Logger.info("Pipeline told to resume recording")
      :ok = StorageMonitor.resume(state.storage_monitor)
    else
      Membrane.Logger.info("Pipeline told to stop recording")
      :ok = StorageMonitor.pause(state.storage_monitor)
    end

    {[reply: :ok], state}
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    :telemetry.execute(@event_prefix ++ [:terminate], %{system_time: System.system_time()}, %{
      device_id: state.device.id
    })

    {[terminate: :normal], state}
  end

  defp build_device_spec(%{type: :file} = device, _state) do
    [child(:file_source, %ExNVR.Pipeline.Source.File{device: device})]
  end

  defp build_device_spec(%{type: :webcam} = device, state) do
    [width, height] = String.split(device.stream_config.resolution, "x")

    [
      child(:source, %Source.Webcm{
        # the path to you usb(check ls /dev/video*)
        device: device.url,
        framerate: device.stream_config.framerate,
        width: String.to_integer(width),
        height: String.to_integer(height)
      })
      |> via_out(:output)
      |> child(:tee, Membrane.Tee)
      |> via_out(:push_output)
      |> via_in(Pad.ref(:main_stream, :video))
      |> get_child(:hls_sink),
      get_child(:tee)
      |> via_out(:push_output)
      |> child({:storage, :main_stream}, %Output.Storage{
        device: state.device,
        target_segment_duration: state.segment_duration,
        correct_timestamp: true
      })
    ]
  end

  defp build_device_spec(%{type: :ip} = device, _state) do
    [child(:rtsp_source, %Source.RTSP{device: device})]
  end

  defp build_main_stream_spec(state) do
    build_main_stream_storage_spec(state) ++
      [
        get_child(:tee)
        |> via_out(:push_output)
        |> via_in(Pad.ref(:main_stream, :video))
        |> get_child(:hls_sink),
        get_child(:tee)
        |> via_out(:push_output)
        |> child({:snapshooter, :main_stream}, ExNVR.Elements.CVSBufferer),
        get_child(:tee)
        |> via_out(:push_output)
        |> child({:stats_reporter, :main_stream}, %VideoStreamStatReporter{
          device_id: state.device.id
        }),
        get_child(:tee)
        |> via_out(:push_output)
        |> via_in(:video)
        |> child(:webrtc, %Output.WebRTC{ice_servers: state.ice_servers})
      ]
  end

  defp build_sub_stream_spec(%{device: device} = state) do
    [
      get_child({:tee, :sub_stream})
      |> via_out(:push_output)
      |> via_in(Pad.ref(:sub_stream, :video))
      |> get_child(:hls_sink),
      get_child({:tee, :sub_stream})
      |> via_out(:push_output)
      |> child({:stats_reporter, :sub_stream}, %VideoStreamStatReporter{
        device_id: device.id,
        stream: :low
      })
    ] ++
      build_sub_stream_storage_spec(device) ++
      build_sub_stream_webrtc_spec(state) ++
      build_sub_stream_bif_spec(state)
  end

  defp build_main_stream_storage_spec(%{record_main_stream?: false}), do: []

  defp build_main_stream_storage_spec(state) do
    [
      get_child(:tee)
      |> via_out(:push_output)
      |> child({:storage, :main_stream}, %Output.Storage{
        device: state.device,
        target_segment_duration: state.segment_duration,
        correct_timestamp: true
      })
    ]
  end

  defp build_sub_stream_storage_spec(%{record_main_stream?: false}), do: []

  defp build_sub_stream_storage_spec(device) do
    case device.storage_config.record_sub_stream do
      :always ->
        [
          get_child({:tee, :sub_stream})
          |> via_out(:push_output)
          |> child({:storage, :sub_stream}, %Output.Storage{
            device: device,
            stream: :low,
            correct_timestamp: true
          })
        ]

      _other ->
        []
    end
  end

  defp build_sub_stream_webrtc_spec(state) do
    [
      get_child({:tee, :sub_stream})
      |> via_out(:push_output)
      |> via_in(:video)
      |> child({:webrtc, :sub_stream}, %Output.WebRTC{ice_servers: state.ice_servers})
    ]
  end

  defp build_sub_stream_bif_spec(state) do
    if state.record_main_stream? and state.device.settings.generate_bif do
      [
        get_child({:tee, :sub_stream})
        |> via_out(:push_output)
        |> child({:thumbnailer, :sub_stream}, %Output.Thumbnailer{
          dest: Device.bif_thumbnails_dir(state.device)
        })
      ]
    else
      []
    end
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

  defp can_add_webrtc_peer(device, track) do
    with {:streaming, true} <- {:streaming, Device.streaming?(device)},
         {:stream_supported, true} <- {:stream_supported, not is_nil(track)} do
      :ok
    else
      {:streaming, false} -> {:error, :offline}
      {:stream_supported, false} -> {:error, :stream_unavailable}
    end
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

  defp ice_servers do
    Application.get_env(:ex_nvr, :ice_servers, "[]") |> Jason.decode(keys: :atoms)
  end
end
