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

  alias ExNVR.RTSP.Source
  alias Membrane.RTP.SessionBin

  defmodule State do
    use Bunch.Access

    @typedoc """
    Pipeline state

    `stream_uri` - the RTSP stream
    `media_options` - the media description got from calling DESCRIBE method on the RTSP uri
    `recordings_temp_dir` - Folder where to store recordings temporarily
    """
    @type t :: %__MODULE__{
            stream_uri: binary(),
            media_options: map(),
            recordings_temp_dir: Path.t()
          }

    @enforce_keys [:stream_uri]

    defstruct @enforce_keys ++
                [
                  media_options: nil,
                  recordings_temp_dir: System.tmp_dir!(),
                  pending_recordings: %{}
                ]
  end

  def start_link(options \\ []) do
    Membrane.Logger.info("Starting a new NVR pipeline with options: #{inspect(options)}")
    Membrane.Pipeline.start_link(__MODULE__, options, name: __MODULE__)
  end

  @impl true
  def handle_init(_ctx, options) do
    state = %State{
      stream_uri: options[:stream_uri]
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
      |> child(:rtp_parser, Membrane.H264.Parser)
      |> child(:segmenter, %ExNVR.Segmenter{
        segment_duration: 60
      })
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification(
        {:new_media_segment, {old_segment_starttime, new_segment_starttime}},
        :segmenter,
        _ctx,
        state
      ) do
    Membrane.Logger.info("""
    New segment: #{new_segment_starttime}
    Start flushing old segment
    """)

    spec = [
      get_child(:segmenter)
      |> via_out(Pad.ref(:output, new_segment_starttime))
      |> child({:h264_mp4_payloader, new_segment_starttime}, Membrane.MP4.Payloader.H264)
      |> child({:mp4_muxer, new_segment_starttime}, Membrane.MP4.Muxer.ISOM)
      |> child({:sink, new_segment_starttime}, %Membrane.File.Sink{
        location: Path.join(state.recordings_temp_dir, "#{new_segment_starttime}.mp4")
      })
    ]

    {[spec: spec],
     update_pending_recordings(state, {old_segment_starttime, new_segment_starttime})}
  end

  @impl true
  def handle_child_notification({:rtsp_connection_lost, _reason}, :rtsp_source, _ctx, state) do
    {[notify_child: {:segmenter, :reset}], state}
  end

  # Once the sink receive end of stream and flush the segment to the filesystem
  # we can delete the childs
  @impl true
  def handle_element_end_of_stream({:sink, seg_ref}, _pad, _ctx, state) do
    children = [
      {:h264_mp4_payloader, seg_ref},
      {:mp4_muxer, seg_ref},
      {:sink, seg_ref}
    ]

    {recording, state} = pop_in(state, [:pending_recordings, seg_ref])

    case ExNVR.Recordings.save(recording) do
      {:ok, _} ->
        File.rm(recording.path)

      {:error, error} ->
        Membrane.Logger.error("""
        Could not save recording #{inspect(recording)}
        #{inspect(error)}
        """)
    end

    {[remove_child: children], state}
  end

  @impl true
  def handle_element_end_of_stream(_child, _pad, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_tick(:playback_timer, _ctx, state) do
    {[stop_timer: :playback_timer, playback: :playing], state}
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

  defp update_pending_recordings(state, {old_segment_starttime, new_segment_starttime}) do
    state =
      put_in(
        state,
        [:pending_recordings, new_segment_starttime],
        %{
          start_date: Membrane.Time.to_datetime(new_segment_starttime),
          path: Path.join(state.recordings_temp_dir, "#{new_segment_starttime}.mp4")
        }
      )

    if old_segment_starttime != nil do
      put_in(
        state,
        [:pending_recordings, old_segment_starttime, :end_date],
        Membrane.Time.to_datetime(new_segment_starttime)
      )
    else
      state
    end
  end
end
