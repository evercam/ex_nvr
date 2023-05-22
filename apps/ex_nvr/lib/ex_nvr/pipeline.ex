defmodule ExNVR.Pipeline do
  @moduledoc """
  Main pipeline that stream videos footages and store them as chunks of configurable duration.

  ## Architecture
  The general architecture of the pipeline is as follows:
    * The pipeline starts first an element called `:rtsp_stream` which is responsible for connecting to the RTSP uri and
    streaming the media packets.
    * Once the pipeline receives a notification about an established session with RTSP server, the `RTP` session bin is
    linked to the output of the RTSP source
    * The new RTP stream is linked to a segmenter, which is responsible for chunking the video footage, it emits a new
    notifcation to the parent each time a new segment starts
    * The pipeline links the output of the `Segmenter` element with an MP4 payloader and muxer and save it to a temporary
    folder
    * Once the video chunk is flused to disk, the Pipeline call `ExNVR.Recordings.save/1` to store the record.

  ## Limitations

  There's some limitation on the pipeline working, the pipeline supports:
    * Only video streams
    * Only one video stream
    * Only H264 encoded streams
  """

  use Membrane.Pipeline

  require Membrane.Logger

  alias ExNVR.Elements.RTSP.Source
  alias Membrane.RTP.SessionBin

  @hls_live_streaming_directory "/home/ghilas/p/Evercam/ex_nvr/data/hls"

  defmodule State do
    @moduledoc false

    use Bunch.Access

    @type hls_state :: :stopped | :starting | :started

    @typedoc """
    Pipeline state

    `device_id` - Id of the device where to pull the media stream
    `stream_uri` - RTSP stream
    `media_options` - Media description got from calling DESCRIBE method on the RTSP uri
    `hls_streaming_state` - The current state of the HLS live streaming
    `hls_pending_callers` - List of callers (pid) that waits for first hls segment to be available
    """
    @type t :: %__MODULE__{
            device_id: binary(),
            stream_uri: binary(),
            media_options: map(),
            hls_streaming_state: hls_state(),
            hls_pending_callers: [GenServer.from()]
          }

    @enforce_keys [:device_id, :stream_uri]

    defstruct @enforce_keys ++
                [
                  media_options: nil,
                  hls_streaming_state: :stopped,
                  hls_pending_callers: []
                ]
  end

  def start_link(options \\ []) do
    Membrane.Logger.info("Starting a new NVR pipeline with options: #{inspect(options)}")
    Membrane.Pipeline.start_link(__MODULE__, options, name: __MODULE__)
  end

  @doc """
  Start HLS live streaming.

  The `segment_name_prefix` is used for generating segments' names
  """
  def start_hls_streaming(segment_name_prefix) do
    Pipeline.call(__MODULE__, {:start_hls_streaming, segment_name_prefix}, 60_000)
  end

  def stop_hls_streaming() do
    Pipeline.call(__MODULE__, :stop_hls_streaming)
  end

  @impl true
  def handle_init(_ctx, options) do
    state = %State{
      device_id: options.device_id,
      stream_uri: options.stream_uri
    }

    source = child(:rtsp_source, %Source{stream_uri: state.stream_uri})

    {[spec: [source]], state}
  end

  @impl true
  def handle_child_notification(
        {:rtsp_setup_complete, media_options},
        :rtsp_source,
        _ctx,
        %State{} = state
      ) do
    if media_options.rtpmap.encoding != "H264" do
      Membrane.Logger.error("Only H264 streams are supported now")
      {[terminate: :normal], state}
    else
      handle_rtsp_stream_setup(media_options, state)
    end
  end

  @impl true
  def handle_child_notification({:new_rtp_stream, ssrc, _pt, _extensions}, _, _ctx, state) do
    spec = [
      get_child(:rtp)
      |> via_out(Pad.ref(:output, ssrc), options: [depayloader: Membrane.RTP.H264.Depayloader])
      |> child(:rtp_parser, %Membrane.H264.Parser{framerate: {0, 0}})
      |> child(:tee, Membrane.Tee.Master)
      |> via_out(:master)
      |> child(:storage_bin, %ExNVR.Elements.StorageBin{
        device_id: state.device_id,
        target_segment_duration: 30
      })
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification({:track_playable, _}, :hls_bin, _ctx, state) do
    replies = Enum.map(state.hls_pending_callers, &{:reply_to, {&1, :ok}})

    {replies, %{state | hls_streaming_state: :started, hls_pending_callers: []}}
  end

  @impl true
  def handle_child_notification(_notification, _element, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_tick(:playback_timer, _ctx, state) do
    {[stop_timer: :playback_timer, playback: :playing], state}
  end

  @impl true
  def handle_call({:start_hls_streaming, _}, _ctx, %{hls_streaming_state: :started} = state) do
    {[reply: :ok], state}
  end

  @impl true
  def handle_call(
        {:start_hls_streaming, _},
        %{from: from},
        %{hls_streaming_state: :starting} = state
      ) do
    {[], %{state | hls_pending_callers: [from | state.hls_pending_callers]}}
  end

  @impl true
  def handle_call(
        {:start_hls_streaming, segment_name_prefix},
        %{from: from},
        %{hls_streaming_state: :stopped} = state
      ) do
    spec = [
      get_child(:tee)
      |> via_out(:copy)
      |> child(:hls_bin, %ExNVR.Elements.HLSBin{
        location: @hls_live_streaming_directory,
        segment_name_prefix: segment_name_prefix
      })
    ]

    clean_hls_directory()

    {[spec: {spec, crash_group: {"hls", :temporary}}],
     %{state | hls_streaming_state: :starting, hls_pending_callers: [from]}}
  end

  @impl true
  def handle_call(:stop_hls_streaming, _ctx, state) do
    {[reply: :ok, remove_child: :hls_bin],
     %{state | hls_streaming_state: :stopped, hls_pending_callers: []}}
  end

  @impl true
  def handle_crash_group_down("hls", _ctx, state) do
    Membrane.Logger.error("Hls group crashed, stopped live streaming...")
    {[], %{state | hls_streaming_state: :stopped}}
  end

  defp handle_rtsp_stream_setup(%{rtpmap: rtpmap} = media_options, state) do
    fmt_mapping =
      Map.put(%{}, rtpmap.payload_type, {String.to_atom(rtpmap.encoding), rtpmap.clock_rate})

    spec = [
      get_child(:rtsp_source)
      |> via_in(Pad.ref(:rtp_input, make_ref()))
      |> child(:rtp, %SessionBin{
        fmt_mapping: fmt_mapping
      })
    ]

    {[spec: spec, start_timer: {:playback_timer, Membrane.Time.milliseconds(300)}],
     %State{state | media_options: media_options}}
  end

  defp clean_hls_directory() do
    @hls_live_streaming_directory
    |> File.ls!()
    |> Enum.each(&File.rm_rf!(Path.join(@hls_live_streaming_directory, &1)))
  end
end
