defmodule ExNVR.Elements.Transcoder do
  @moduledoc """
  Transcode video streams.
  """

  use Membrane.Filter

  import ExMP4.Helper

  alias ExNVR.AV.{Decoder, Encoder}
  alias Membrane.{H264, H265}

  @original_time_base Membrane.Time.seconds(1)
  @dest_time_base 90_000

  def_input_pad :input,
    accepted_format: any_of(%H264{stream_structure: :annexb}, %H265{stream_structure: :annexb})

  def_output_pad :output, accepted_format: %H264{stream_structure: :annexb}

  def_options height: [type: :integer]

  @impl true
  def handle_init(_ctx, opts) do
    {[], %{decoder: nil, encoder: nil, height: opts.height, stream_format: nil}}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    codec =
      case stream_format do
        %H264{} -> :h264
        %H265{} -> :hevc
      end

    cond do
      is_nil(state.stream_format) ->
        width = div(stream_format.width * state.height, stream_format.height)
        width = width - rem(width, 4)

        decoder = Decoder.new(codec, out_height: state.height, out_width: width)

        encoder =
          Encoder.new(:h264,
            width: width,
            height: state.height,
            format: :yuv420p,
            time_base: {1, @dest_time_base},
            gop_size: 32,
            profile: encoder_profile(),
            max_b_frames: 0
          )

        out_stream_format = %H264{
          alignment: :au,
          height: state.height,
          profile: encoder_profile(),
          stream_structure: :annexb,
          width: width
        }

        {[stream_format: {:output, out_stream_format}],
         %{state | encoder: encoder, decoder: decoder, stream_format: stream_format}}

      stream_format == state.stream_format ->
        {[], state}

      true ->
        raise "Incompatible stream format"
    end
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    dts = buffer.dts && timescalify(buffer.dts, @original_time_base, @dest_time_base)
    pts = buffer.pts && timescalify(buffer.pts, @original_time_base, @dest_time_base)

    state.decoder
    |> Decoder.decode(buffer.payload, dts: dts, pts: pts)
    |> Enum.flat_map(&Encoder.encode(state.encoder, &1))
    |> Enum.map(&map_to_buffer/1)
    |> then(&{[buffer: {:output, &1}], state})
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    buffers =
      state.decoder
      |> Decoder.flush()
      |> Enum.flat_map(&Encoder.encode(state.encoder, &1))
      |> Kernel.++(Encoder.flush(state.encoder))
      |> Enum.map(&map_to_buffer/1)

    {[buffer: {:output, buffers}, forward: :output], state}
  end

  defp map_to_buffer(packet) do
    metadata = %{h264: %{key_frame?: packet.keyframe?}}

    %Membrane.Buffer{
      payload: packet.data,
      dts: packet.dts && timescalify(packet.dts, @dest_time_base, @original_time_base),
      pts: packet.pts && timescalify(packet.pts, @dest_time_base, @original_time_base),
      metadata: metadata
    }
  end

  defp encoder_profile, do: "Baseline"
end
