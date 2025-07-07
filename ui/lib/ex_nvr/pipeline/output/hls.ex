defmodule ExNVR.Pipeline.Output.HLS do
  @moduledoc """
  Output element that create HLS playlists from audio/video
  """

  use Membrane.Sink

  require ExNVR.Utils

  import ExMP4.Helper
  import ExNVR.MediaUtils

  alias __MODULE__.{MultiFileWriter, Variant}
  alias ExMP4.{Box, FWriter}
  alias ExNVR.HLS.MultivariantPlaylist
  alias ExNVR.Pipeline.Event.StreamClosed
  alias ExNVR.Utils
  alias Membrane.{Buffer, Event, H264, H265, ResourceGuard}

  @segment_duration 2 * 90_000

  def_input_pad :main_stream,
    accepted_format: any_of(%H264{alignment: :au}, %H265{alignment: :au}),
    availability: :on_request

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

    ResourceGuard.register(ctx.resource_guard, fn ->
      File.rm_rf!(options.location)
    end)

    state = %{
      variants: %{},
      location: options.location,
      playlist: MultivariantPlaylist.new([])
    }

    {[], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(variant_name, _ref), _ctx, state) do
    playlist = MultivariantPlaylist.add_variant(state.playlist, variant_name)
    variants = Map.put(state.variants, variant_name, Variant.new(variant_name))
    {[], %{state | variants: variants, playlist: playlist}}
  end

  @impl true
  def handle_stream_format(Pad.ref(variant_name, _ref) = pad, stream_format, ctx, state) do
    old_stream_format = ctx.pads[pad].stream_format
    variant = state.variants[variant_name]

    state =
      cond do
        is_nil(old_stream_format) ->
          put_in(state, [:variants, variant.name], %{
            variant
            | track: track_from_stream_format(stream_format)
          })

        codec_changed?(old_stream_format, stream_format) ->
          raise "HLS does not support codec change"

        old_stream_format != stream_format ->
          :ok = variant.writer |> FWriter.flush_fragment() |> FWriter.close()

          variant =
            Variant.reset_writer(variant)
            |> Variant.inc_segment_count()
            |> Map.merge(%{
              track: track_from_stream_format(stream_format),
              count_media_init: variant.count_media_init,
              insert_discontinuity?: true
            })

          %{state | variants: Map.put(state.variants, variant_name, variant)}

        true ->
          state
      end

    {[], state}
  end

  @impl true
  def handle_event(Pad.ref(variant_name, _ref), %Event.Discontinuity{}, _ctx, state) do
    {[], handle_discontinuity(state, variant_name)}
  end

  @impl true
  def handle_event(Pad.ref(variant_name, _ref), %StreamClosed{}, _ctx, state) do
    {[], handle_discontinuity(state, variant_name)}
  end

  @impl true
  def handle_buffer(Pad.ref(variant_name, _ref), buffer, _ctx, state) do
    state = do_handle_buffer(state, state.variants[variant_name], buffer)
    {[], state}
  end

  @impl true
  def handle_info({:init_header, variant_name, uri}, _ctx, state) do
    playlist = MultivariantPlaylist.add_init_header(state.playlist, variant_name, uri)
    {[], %{state | playlist: playlist}}
  end

  @impl true
  def handle_info({:segment, variant_name, segment}, _ctx, state) do
    variant = state.variants[variant_name]

    {playlist, discarded} =
      MultivariantPlaylist.add_segment(state.playlist, variant_name, segment)

    playlist =
      if variant.insert_discontinuity?,
        do: MultivariantPlaylist.add_discontinuity(playlist, variant_name),
        else: playlist

    {actions, variant} =
      if variant.playable?,
        do: {[], variant},
        else: {[notify_parent: {:track_playable, variant_name}], %{variant | playable?: true}}

    serialize(playlist, state.location)
    delete_discarded_segments(discarded, state.location)

    {actions,
     %{
       state
       | playlist: playlist,
         variants:
           Map.put(state.variants, variant_name, %{variant | insert_discontinuity?: false})
     }}
  end

  @impl true
  def handle_info(_message, _ctx, state) do
    {[], state}
  end

  defp do_handle_buffer(state, %{last_buffer: nil} = variant, buffer)
       when Utils.keyframe(buffer) do
    {variant, sps} =
      case variant.track.media do
        :h264 ->
          {{sps, pps}, _au} = MediaCodecs.H264.pop_parameter_sets(buffer.payload)
          variant = %{variant | track: %{variant.track | priv_data: Box.Avcc.new(sps, pps)}}
          {variant, MediaCodecs.H264.NALU.parse(List.first(sps))}

        :h265 ->
          {{vps, sps, pps}, _au} = MediaCodecs.H265.pop_parameter_sets(buffer.payload)
          variant = %{variant | track: %{variant.track | priv_data: get_hevc_dcr(vps, sps, pps)}}
          {variant, MediaCodecs.H265.NALU.parse(List.first(sps))}
      end

    playlist =
      MultivariantPlaylist.update_settings(state.playlist, variant.name,
        resolution: resolution(variant.track),
        codecs: codecs(variant.track.media, sps.content)
      )

    writer_opts = [
      dir: state.location,
      init_write: &send(self(), {:init_header, variant.name, &1}),
      segment_write: &send(self(), {:segment, variant.name, &1}),
      segment_name_prefix: variant.name,
      start_segment_number: variant.count_segments,
      start_init_number: variant.count_media_init
    ]

    writer =
      writer_opts
      |> FWriter.new!([variant.track], [moof_base_offset: true, duration: false], MultiFileWriter)
      |> FWriter.create_segment()
      |> FWriter.create_fragment()

    variant = %{
      Variant.inc_media_init_count(variant)
      | writer: writer,
        last_buffer: buffer,
        track: FWriter.track(writer, :video)
    }

    %{state | variants: Map.put(state.variants, variant.name, variant), playlist: playlist}
  end

  defp do_handle_buffer(state, %{last_buffer: nil}, _buffer) do
    state
  end

  defp do_handle_buffer(state, %{last_buffer: last_buffer} = variant, buffer) do
    duration = Buffer.get_dts_or_pts(buffer) - Buffer.get_dts_or_pts(last_buffer)
    keyframe? = Utils.keyframe(last_buffer)
    timescale = variant.track.timescale

    sample = %ExMP4.Sample{
      track_id: variant.track.id,
      dts: timescalify(Buffer.get_dts_or_pts(last_buffer), :nanosecond, timescale),
      pts: timescalify(last_buffer.pts, :nanosecond, timescale),
      sync?: keyframe?,
      payload: MediaCodecs.H264.annexb_to_elementary_stream(last_buffer.payload),
      duration: ExMP4.Helper.timescalify(duration, :nanosecond, timescale)
    }

    variant =
      if keyframe? and variant.segment_duration >= @segment_duration do
        writer =
          variant.writer
          |> FWriter.flush_fragment()
          |> FWriter.create_segment()
          |> FWriter.create_fragment()
          |> FWriter.write_sample(sample)

        %{
          Variant.inc_segment_count(variant)
          | writer: writer,
            segment_duration: sample.duration
        }
      else
        writer = FWriter.write_sample(variant.writer, sample)
        %{variant | writer: writer, segment_duration: variant.segment_duration + sample.duration}
      end

    put_in(state, [:variants, variant.name], %{variant | last_buffer: buffer})
  end

  defp handle_discontinuity(state, variant_name) do
    variant = state.variants[variant_name]

    if writer = variant.writer do
      writer |> FWriter.flush_fragment() |> FWriter.close()

      variant =
        variant
        |> Variant.reset_writer()
        |> Variant.inc_segment_count()
        |> Map.put(:insert_discontinuity?, true)

      %{state | variants: Map.put(state.variants, variant_name, variant)}
    else
      state
    end
  end

  defp serialize(playlist, location) do
    {master, variants} = MultivariantPlaylist.serialize(playlist)

    File.write!(Path.join(location, "index.m3u8"), master)

    Enum.each(variants, fn {name, content} ->
      File.write!(Path.join(location, "#{name}.m3u8"), content)
    end)
  end

  defp delete_discarded_segments(discarded, location) do
    Enum.each(discarded, fn
      %ExM3U8.Tags.Segment{uri: uri} -> File.rm!(Path.join(location, uri))
      %ExM3U8.Tags.MediaInit{uri: uri} -> File.rm!(Path.join(location, uri))
      _other -> :ok
    end)
  end

  defp codec_changed?(%module{}, %module{}), do: false
  defp codec_changed?(_old, _new), do: true

  defp resolution(track), do: {track.width, track.height}

  defp codecs(:h264, sps), do: MediaCodecs.H264.SPS.mime_type(sps, "avc1")
  defp codecs(:h265, sps), do: MediaCodecs.H265.SPS.mime_type(sps, "hvc1")
end
