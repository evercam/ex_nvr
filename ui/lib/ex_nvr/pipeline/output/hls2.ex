defmodule ExNVR.Pipeline.Output.HLS2 do
  @moduledoc """
  Output element that create HLS playlists from audio/video
  """

  use Membrane.Sink

  require ExNVR.Utils

  import ExMP4.Helper
  import ExNVR.MediaUtils

  alias ExMP4.{Box, FWriter}
  alias ExNVR.Pipeline.Event.StreamClosed
  alias ExNVR.Pipeline.Output.HLS.{M3U8Writer, MultiFileWriter}
  alias ExNVR.Utils
  alias Membrane.{Buffer, Event, H264, H265, ResourceGuard}

  @segment_duration 2 * 90_000
  @timescale 90_000

  def_input_pad :main_stream,
    accepted_format: any_of(%H264{alignment: :au}, %H265{alignment: :au}),
    availability: :on_request,
    options: [
      resolution: [
        spec: non_neg_integer() | nil,
        default: nil,
        description: """
        Transcode the video to the provided resolution.

        The resolution denotes the height of the video. e.g. 720p
        """
      ]
    ]

  def_input_pad :sub_stream,
    accepted_format: any_of(%H264{alignment: :au}, %H265{alignment: :au}),
    availability: :on_request

  def_options location: [
                spec: Path.t(),
                description: """
                Directory where to save the generated files
                """
              ]

  @impl true
  def handle_init(ctx, %__MODULE__{} = options) do
    File.rm_rf(options.location)
    File.mkdir_p!(options.location)

    {:ok, pid} =
      M3U8Writer.start_link(
        location: options.location,
        playlist_type: :multivariant
      )

    ResourceGuard.register(ctx.resource_guard, fn ->
      File.rm_rf!(options.location)
    end)

    state = %{
      streams: %{},
      location: options.location,
      manifest: pid
    }

    {[], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(stream_type, _ref), _ctx, state) do
    :ok = M3U8Writer.add_playlist(state.manifest, stream_type)
    {[], put_in(state, [:streams, stream_type], init_stream(stream_type))}
  end

  # @impl true
  # def handle_child_notification({:track_playable, track_id}, :sink, _ctx, state) do
  #   {[notify_parent: {:track_playable, track_id}], state}
  # end

  @impl true
  def handle_stream_format(Pad.ref(stream_type, _ref) = pad, stream_format, ctx, state) do
    old_stream_format = ctx.pads[pad].stream_format
    stream = do_handle_stream_format(state.streams[stream_type], old_stream_format, stream_format)
    {[], put_in(state, [:streams, stream_type], stream)}
  end

  @impl true
  def handle_event(Pad.ref(stream_type, _ref), %Event.Discontinuity{}, _ctx, state) do
    {[], handle_discontinuity(state, stream_type)}
  end

  @impl true
  def handle_event(Pad.ref(stream_type, _ref), %StreamClosed{}, _ctx, state) do
    {[], handle_discontinuity(state, stream_type)}
  end

  @impl true
  def handle_buffer(Pad.ref(stream_type, _ref), buffer, _ctx, state) do
    stream = do_handle_buffer(state, state.streams[stream_type], buffer)
    {[], put_in(state, [:streams, stream_type], stream)}
  end

  defp do_handle_buffer(state, %{last_buffer: nil} = stream, buffer)
       when Utils.keyframe(buffer) do
    manifest = state.manifest
    stream_type = stream.type

    {stream, sps} =
      case stream.track.media do
        :h264 ->
          {{sps, pps}, _au} = MediaCodecs.H264.pop_parameter_sets(buffer.payload)
          stream = %{stream | track: %{stream.track | priv_data: Box.Avcc.new(sps, pps)}}
          {stream, MediaCodecs.H264.parse_nalu(List.first(sps))}

        :h265 ->
          {{vps, sps, pps}, _au} = MediaCodecs.H265.pop_parameter_sets(buffer.payload)
          stream = %{stream | track: %{stream.track | priv_data: get_hevc_dcr(vps, sps, pps)}}
          {stream, MediaCodecs.H265.parse_nalu(List.first(sps))}
      end

    :ok =
      M3U8Writer.update_playlist_settings(state.manifest, stream_type,
        resolution: resolution(stream.track),
        codecs: codecs(stream.track, sps.content)
      )

    writer_opts = [
      dir: state.location,
      init_write: &M3U8Writer.add_init_header(manifest, stream_type, &1),
      segment_write: &M3U8Writer.add_segment(manifest, stream_type, {&1, &2, &3}),
      segment_name_prefix: stream_type,
      start_segment_number: M3U8Writer.total_segments(manifest, stream_type)
    ]

    writer =
      writer_opts
      |> FWriter.new!([stream.track], [moof_base_offset: true, duration: false], MultiFileWriter)
      |> FWriter.create_segment()
      |> FWriter.create_fragment()

    %{stream | writer: writer, last_buffer: buffer, track: FWriter.track(writer, :video)}
  end

  defp do_handle_buffer(_state, %{last_buffer: nil} = stream, _buffer) do
    stream
  end

  defp do_handle_buffer(_state, %{last_buffer: last_buffer} = stream, buffer) do
    duration = Buffer.get_dts_or_pts(buffer) - Buffer.get_dts_or_pts(last_buffer)
    keyframe? = Utils.keyframe(last_buffer)
    timescale = stream.track.timescale

    sample = %ExMP4.Sample{
      track_id: stream.track.id,
      dts: timescalify(Buffer.get_dts_or_pts(last_buffer), :nanosecond, timescale),
      pts: timescalify(last_buffer.pts, :nanosecond, timescale),
      sync?: keyframe?,
      payload: MediaCodecs.H264.annexb_to_elementary_stream(last_buffer.payload),
      duration: ExMP4.Helper.timescalify(duration, :nanosecond, timescale)
    }

    stream =
      if keyframe? and stream.segment_duration >= @segment_duration do
        writer =
          stream.writer
          |> FWriter.flush_fragment()
          |> FWriter.create_segment()
          |> FWriter.create_fragment()
          |> FWriter.write_sample(sample)

        %{stream | writer: writer, segment_duration: sample.duration}
      else
        writer = FWriter.write_sample(stream.writer, sample)
        %{stream | writer: writer, segment_duration: stream.segment_duration + sample.duration}
      end

    %{stream | last_buffer: buffer}
  end

  defp do_handle_stream_format(stream, old_stream_format, stream_format) do
    if is_nil(old_stream_format) do
      %{stream | track: new_track(stream_format)}
    else
      stream
    end
  end

  defp handle_discontinuity(state, stream_type) do
    stream = state.streams[stream_type]

    if writer = stream.writer do
      writer |> FWriter.flush_fragment() |> FWriter.close()
    end

    :ok = M3U8Writer.add_discontinuity(state.manifest, stream_type)
    put_in(state, [:streams, stream_type], %{init_stream(stream_type) | track: stream.track})
  end

  defp init_stream(stream_type) do
    %{
      type: stream_type,
      writer: nil,
      last_buffer: nil,
      track: nil,
      segment_duration: 0
    }
  end

  defp new_track(stream_format) do
    media =
      case stream_format do
        %H264{} -> :h264
        %H265{} -> :h265
      end

    %ExMP4.Track{
      type: :video,
      media: media,
      width: stream_format.width,
      height: stream_format.height,
      timescale: @timescale
    }
  end

  defp resolution(track), do: {track.width, track.height}

  defp codecs(track, sps) do
    case track.media do
      :h264 ->
        compatibility =
          <<sps.constraint_set0::1, sps.constraint_set1::1, sps.constraint_set2::1,
            sps.constraint_set3::1, sps.constraint_set4::1, sps.constraint_set5::1, 0::2>>

        "avc1." <> Base.encode16(<<sps.profile_idc, compatibility::binary, sps.level_idc>>)

      :h265 ->
        "hvc1.#{sps.profile_idc}.4.#{tier(sps.tier_flag)}#{sps.level_idc}.B0"
    end
  end

  defp tier(0), do: "L"
  defp tier(1), do: "H"
end
