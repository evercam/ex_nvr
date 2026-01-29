defmodule ExNVR.Pipeline.Output.HLS do
  @moduledoc """
  Output element that create HLS playlists from audio/video
  """

  use Membrane.Sink

  require ExNVR.Utils

  alias ExNVR.Pipeline.Event.StreamClosed
  alias ExNVR.Utils
  alias Membrane.{Buffer, Event, H264, H265, ResourceGuard}

  def_input_pad :video, accepted_format: any_of(%H264{alignment: :au}, %H265{alignment: :au})

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

    pid = self()

    writer =
      HLX.Writer.new!(
        storage_dir: options.location,
        type: :master,
        max_segments: 6,
        on_segment_created: fn _id, segment ->
          send(pid, {:hls_segment_created, segment})
        end
      )

    variant = %{name: :video, last_buffer: nil}

    {[],
     %{variants: %{video: variant}, location: options.location, writer: writer, playable?: false}}
  end

  @impl true
  def handle_stream_format(:video, stream_format, ctx, state) do
    variant_name = "video"
    old_stream_format = ctx.pads[:video].stream_format

    state =
      cond do
        is_nil(old_stream_format) ->
          track = from_stream_format(stream_format)
          writer = HLX.Writer.add_variant!(state.writer, variant_name, tracks: [track])
          %{state | writer: writer}

        codec_changed?(old_stream_format, stream_format) ->
          raise "HLS does not support codec change"

        old_stream_format != stream_format ->
          writer = HLX.Writer.add_discontinuity(state.writer, variant_name)
          %{state | writer: writer}

        true ->
          state
      end

    {[], state}
  end

  @impl true
  def handle_event(:video, %Event.Discontinuity{}, _ctx, state) do
    {[], handle_discontinuity(state, "video")}
  end

  @impl true
  def handle_event(:video, %StreamClosed{}, _ctx, state) do
    {[], handle_discontinuity(state, "video")}
  end

  @impl true
  def handle_buffer(:video, buffer, _ctx, state) do
    state = do_handle_buffer(state, state.variants[:video], buffer)
    {[], state}
  end

  @impl true
  def handle_info({:hls_segment_created, _segment}, _ctx, %{playable?: false} = state) do
    {[notify_parent: {:track_playable, nil}], %{state | playable?: true}}
  end

  def handle_info({:hls_segment_created, _segment}, _ctx, state) do
    {[], state}
  end

  defp do_handle_buffer(state, %{last_buffer: nil} = variant, buffer)
       when Utils.keyframe(buffer) do
    variant = %{variant | last_buffer: buffer}
    %{state | variants: Map.put(state.variants, variant.name, variant)}
  end

  defp do_handle_buffer(state, %{last_buffer: nil}, _buffer) do
    state
  end

  defp do_handle_buffer(state, %{last_buffer: last_buffer} = variant, buffer) do
    sample = %HLX.Sample{
      track_id: 1,
      dts: Buffer.get_dts_or_pts(last_buffer),
      pts: last_buffer.pts,
      sync?: Utils.keyframe(last_buffer),
      payload: last_buffer.payload,
      duration: Buffer.get_dts_or_pts(buffer) - Buffer.get_dts_or_pts(last_buffer)
    }

    writer = HLX.Writer.write_sample(state.writer, to_string(variant.name), sample)
    variants = Map.update!(state.variants, variant.name, &%{&1 | last_buffer: buffer})
    %{state | writer: writer, variants: variants}
  end

  defp handle_discontinuity(state, variant_name) do
    writer = HLX.Writer.add_discontinuity(state.writer, variant_name)

    variants =
      Map.update!(
        state.variants,
        String.to_existing_atom(variant_name),
        &%{&1 | last_buffer: nil}
      )

    %{state | writer: writer, variants: variants}
  end

  defp codec_changed?(%module{}, %module{}), do: false
  defp codec_changed?(_old, _new), do: true

  def from_stream_format(stream_format) do
    media =
      case stream_format do
        %Membrane.H264{} -> :h264
        %Membrane.H265{} -> :hevc
      end

    %HLX.Track{
      id: 1,
      type: :video,
      codec: media,
      width: stream_format.width,
      height: stream_format.height,
      timescale: Membrane.Time.second()
    }
  end
end
