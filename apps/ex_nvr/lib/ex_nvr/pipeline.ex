defmodule ExNVR.Pipeline do
  @moduledoc """
  Main pipeline that stream video footages and store them as chunks of configurable duration.

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
    * Only H264 encoded streams
  """

  use Membrane.Pipeline

  require Membrane.Logger

  alias ExNVR.Elements.RTSP.Source
  alias ExNVR.Utils
  alias Membrane.RTP.SessionBin

  defmodule State do
    @moduledoc false

    use Bunch.Access

    @default_segment_duration 60

    @typedoc """
    Pipeline state

    `device_id` - Id of the device where to pull the media stream
    `stream_uri` - RTSP stream
    `video_track` - Media description got from calling DESCRIBE method on the RTSP uri
    `sub_stream_video_track` - Media description of the sub stream got from calling DESCRIBE method on the RTSP uri
    `segment_duration` - The duration of each video chunk saved by the storage bin.
    `supervisor_pid` - The supervisor pid of this pipeline (needed to stop a pipeline)
    """
    @type t :: %__MODULE__{
            device_id: binary(),
            stream_uri: binary(),
            sub_stream_uri: binary(),
            video_track: ExNVR.MediaTrack.t(),
            sub_stream_video_track: ExNVR.MediaTrack.t(),
            segment_duration: non_neg_integer(),
            supervisor_pid: pid()
          }

    @enforce_keys [:device_id, :stream_uri]

    defstruct @enforce_keys ++
                [
                  sub_stream_uri: nil,
                  segment_duration: @default_segment_duration,
                  video_track: nil,
                  sub_stream_video_track: nil,
                  hls_streaming_state: :stopped,
                  hls_pending_callers: [],
                  supervisor_pid: nil
                ]
  end

  def start_link(options \\ []) do
    Membrane.Logger.info("Starting a new NVR pipeline with options: #{inspect(options)}")

    with {:ok, sup_pid, pid} = res <-
           Membrane.Pipeline.start_link(__MODULE__, options,
             name: pipeline_name(options[:device_id])
           ) do
      send(pid, {:pipeline_supervisor, sup_pid})
      res
    end
  end

  def supervisor(device_id) do
    Pipeline.call(pipeline_name(device_id), :pipeline_supervisor)
  end

  @impl true
  def handle_init(_ctx, options) do
    state = %State{
      device_id: options[:device_id],
      stream_uri: options[:stream_uri],
      sub_stream_uri: options[:sub_stream_uri],
      segment_duration: options[:segment_duration] || 60
    }

    hls_sink = %ExNVR.Elements.HLSBin{
      location: Path.join(Utils.hls_dir(state.device_id), "live"),
      segment_name_prefix: "live"
    }

    spec =
      [
        child(:rtsp_source, %Source{stream_uri: state.stream_uri}),
        {child(:hls_sink, hls_sink, get_if_exists: true), crash_group: {"hls", :temporary}}
      ] ++
        if state.sub_stream_uri,
          do: [child({:rtsp_source, :sub_stream}, %Source{stream_uri: state.sub_stream_uri})],
          else: []

    {[spec: spec, playback: :playing], state}
  end

  @impl true
  def handle_child_notification({:connection_lost, ref}, _elem, ctx, state) do
    ctx.children
    |> Map.keys()
    |> Enum.filter(fn
      {{_, ^ref}, _} -> true
      {{_, :sub_stream, ^ref}, _} -> true
      _ -> false
    end)
    |> then(&{[remove_child: &1], state})
  end

  @impl true
  def handle_child_notification(
        {:rtsp_setup_complete, video_track, ref},
        :rtsp_source,
        _ctx,
        %State{} = state
      ) do
    if video_track.codec != :H264 do
      Membrane.Logger.error("Only H264 streams are supported now")
      {[terminate: :normal], state}
    else
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
        %{video_track: video_track} = state
      ) do
    spec = [
      get_child({:rtp, ref})
      |> via_out(Pad.ref(:output, ssrc), options: [depayloader: Membrane.RTP.H264.Depayloader])
      |> child({:rtp_parser, ref}, %Membrane.H264.Parser{
        sps: <<0, 0, 1>> <> video_track.sps,
        pps: <<0, 0, 1>> <> video_track.pps,
        framerate: {0, 0}
      })
      |> child({:tee, ref}, Membrane.Tee.Master)
      |> via_out(:master)
      |> child({:storage_bin, ref}, %ExNVR.Elements.StorageBin{
        device_id: state.device_id,
        target_segment_duration: state.segment_duration,
        sps: video_track.sps,
        pps: video_track.pps
      }),
      get_child({:tee, ref})
      |> via_out(:copy)
      |> via_in(Pad.ref(:input, :main_stream))
      |> get_child(:hls_sink)
    ]

    {[spec: spec], state}
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
      |> via_in(Pad.ref(:input, :sub_stream))
      |> get_child(:hls_sink)
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification({:track_playable, _}, _, _ctx, state) do
    replies = Enum.map(state.hls_pending_callers, &{:reply_to, {&1, :ok}})

    {replies, %{state | hls_streaming_state: :started, hls_pending_callers: []}}
  end

  @impl true
  def handle_child_notification(_notification, _element, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_crash_group_down("hls", _ctx, state) do
    Membrane.Logger.error("Hls group crashed, stop live streaming...")
    {[], %{state | hls_streaming_state: :stopped}}
  end

  @impl true
  def handle_info({:pipeline_supervisor, pid}, _ctx, state) do
    {[], %{state | supervisor_pid: pid}}
  end

  @impl true
  def handle_call(:pipeline_supervisor, _ctx, state) do
    {[reply: state.supervisor_pid], state}
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

  defp pipeline_name(device_id), do: :"pipeline_#{device_id}"
end
