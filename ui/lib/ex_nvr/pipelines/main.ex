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

  alias ExNVR.{Devices, Recordings, Utils}
  alias ExNVR.Elements.VideoStreamStatReporter
  alias ExNVR.Model.Device
  alias ExNVR.Pipeline.{Output, Source, Track}

  @type encoding :: :H264 | :H265

  @event_prefix [:ex_nvr, :main_pipeline]
  @default_segment_duration Membrane.Time.seconds(60)
  @default_ice_servers [%{urls: "stun:stun.l.google.com:19302"}]

  defmodule State do
    @moduledoc false

    use Bunch.Access

    alias ExNVR.Pipeline.Track
    alias ExNVR.Model.Device

    @default_segment_duration Membrane.Time.seconds(60)

    @typedoc """
    Pipeline state

    `device` - The device from where to pull the media streams
    `segment_duration` - The duration of each video chunk saved by the storage bin.
    `supervisor_pid` - The supervisor pid of this pipeline (needed to stop a pipeline)
    `live_snapshot_waiting_pids` - List of pid waiting for live snapshot request to be completed
    `main_stream_video_track` - The main stream video track.
    `sub_stream_video_track` - The sub stream video track.
    `record_main_stream?` - Whether to record the main stream or not.
    `ice_servers` - The list of ICE or/and TURN servers to use for WebRTC.
    """
    @type t :: %__MODULE__{
            device: Device.t(),
            segment_duration: Membrane.Time.t(),
            supervisor_pid: pid(),
            live_snapshot_waiting_pids: list(),
            main_stream_video_track: Track.t(),
            sub_stream_video_track: Track.t() | nil,
            record_main_stream?: boolean(),
            ice_servers: list(map())
          }

    @enforce_keys [:device]

    defstruct @enforce_keys ++
                [
                  segment_duration: @default_segment_duration,
                  supervisor_pid: nil,
                  live_snapshot_waiting_pids: [],
                  main_stream_video_track: nil,
                  sub_stream_video_track: nil,
                  record_main_stream?: true,
                  ice_servers: []
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
      record_main_stream?: device.type != :file,
      ice_servers: ice_servers
    }

    {[], state}
  end

  @impl true
  def handle_setup(_ctx, %{device: device} = state) do
    spec =
      [
        child(:hls_sink, %Output.HLS{
          location: Path.join(Utils.hls_dir(device.id), "live"),
          segment_name_prefix: "live"
        }),
        child(:snapshooter, ExNVR.Elements.SnapshotBin)
      ] ++ build_device_spec(device)

    # Set device state and make last active run inactive
    # may happens on application crash
    device_state = if state.device.type == :file, do: :recording, else: :failed
    Recordings.deactivate_runs(state.device)
    {[spec: spec], maybe_update_device_and_report(state, device_state)}
  end

  @impl true
  def handle_child_notification(
        {:main_stream, ssrc, track},
        child_name,
        _ctx,
        %State{} = state
      ) do
    state = maybe_update_device_and_report(state, :recording)
    old_track = state.main_stream_video_track

    spec = [
      get_child(child_name)
      |> via_out(Pad.ref(:main_stream_output, ssrc))
      |> via_in(Pad.ref(:video, make_ref()))
      |> get_child(:tee)
    ]

    main_spec = if is_nil(old_track), do: build_main_stream_spec(state, track.encoding), else: []

    {[spec: main_spec ++ spec], %{state | main_stream_video_track: track}}
  end

  @impl true
  def handle_child_notification(
        {:sub_stream, ssrc, track},
        child_name,
        _ctx,
        %State{} = state
      ) do
    old_track = state.sub_stream_video_track
    spec = if is_nil(old_track), do: build_sub_stream_spec(state, track.encoding), else: []

    spec =
      spec ++
        [
          get_child(child_name)
          |> via_out(Pad.ref(:sub_stream_output, ssrc))
          |> via_in(Pad.ref(:video, make_ref()))
          |> get_child({:tee, :sub_stream})
        ]

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
      {source, track} =
        if Enum.member?(childs, {:tee, :sub_stream}) do
          {get_child({:tee, :sub_stream}), state.sub_stream_video_track}
        else
          {get_child(:tee), state.main_stream_video_track}
        end

      spec = [
        source
        |> via_out(:video_output)
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
        {[spec: link_live_snapshot_elements(state, image_format)],
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
  def handle_call({:peer_message, stream_type, message}, ctx, state) do
    child =
      case stream_type do
        :high -> :webrtc
        :low -> {:webrtc, :sub_stream}
      end

    {[reply: :ok, notify_child: {child, message}], state}
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    :telemetry.execute(@event_prefix ++ [:terminate], %{system_time: System.system_time()}, %{
      device_id: state.device.id
    })

    {[terminate: :normal], state}
  end

  defp build_device_spec(%{type: :file} = device) do
    [child(:file_source, %ExNVR.Pipeline.Source.File{device: device})]
  end

  defp build_device_spec(device) do
    [child(:rtsp_source, %Source.RTSP{device: device})]
  end

  defp build_main_stream_spec(state, encoding) do
    spec = [child(:tee, ExNVR.Elements.FunnelTee)]

    spec =
      if state.record_main_stream? do
        spec ++
          [
            get_child(:tee)
            |> via_out(:video_output)
            |> child({:storage_bin, :main_stream}, %Output.Storage{
              device: state.device,
              target_segment_duration: state.segment_duration,
              correct_timestamp: true
            })
          ]
      else
        spec
      end

    spec ++
      [
        get_child(:tee)
        |> via_out(:video_output)
        |> via_in(Pad.ref(:video, :main_stream), options: [encoding: encoding])
        |> get_child(:hls_sink),
        get_child(:tee)
        |> via_out(:video_output)
        |> child({:cvs_bufferer, :main_stream}, ExNVR.Elements.CVSBufferer),
        get_child(:tee)
        |> via_out(:video_output)
        |> child({:stats_reporter, :main_stream}, %VideoStreamStatReporter{
          device_id: state.device.id
        }),
        get_child(:tee)
        |> via_out(:video_output)
        |> via_in(:video)
        |> child(:webrtc, %Output.WebRTC{ice_servers: state.ice_servers})
      ]
  end

  defp build_sub_stream_spec(%{device: device} = state, encoding) do
    [
      child({:tee, :sub_stream}, ExNVR.Elements.FunnelTee)
      |> via_out(:video_output)
      |> via_in(Pad.ref(:video, :sub_stream), options: [encoding: encoding])
      |> get_child(:hls_sink),
      get_child({:tee, :sub_stream})
      |> via_out(:video_output)
      |> child({:stats_reporter, :sub_stream}, %VideoStreamStatReporter{
        device_id: device.id,
        stream: :low
      })
    ] ++
      build_sub_stream_storage_spec(device) ++
      build_sub_stream_webrtc_spec(state) ++
      build_sub_stream_bif_spec(device)
  end

  defp build_sub_stream_storage_spec(device) do
    case device.storage_config.record_sub_stream do
      :always ->
        [
          get_child({:tee, :sub_stream})
          |> via_out(:video_output)
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
      |> via_out(:video_output)
      |> via_in(:video)
      |> child({:webrtc, :sub_stream}, %Output.WebRTC{ice_servers: state.ice_servers})
    ]
  end

  defp build_sub_stream_bif_spec(device) do
    if device.settings.generate_bif do
      [
        get_child({:tee, :sub_stream})
        |> via_out(:video_output)
        |> child({:thumbnailer, :sub_stream}, %Output.Thumbnailer{
          dest: Device.bif_thumbnails_dir(device)
        })
      ]
    else
      []
    end
  end

  defp link_live_snapshot_elements(state, image_format) do
    ref = make_ref()

    [
      get_child({:cvs_bufferer, :main_stream})
      |> via_out(Pad.ref(:output, ref))
      |> via_in(Pad.ref(:input, ref),
        options: [format: image_format, encoding: state.main_stream_video_track.encoding]
      )
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

  defp ice_servers() do
    Application.get_env(:ex_nvr, :ice_servers, "[]") |> Jason.decode()
  end
end
