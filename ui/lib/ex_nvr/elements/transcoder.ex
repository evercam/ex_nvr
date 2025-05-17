defmodule ExNVR.Elements.Transcoder do
  @moduledoc """
  Transcode video streams.
  """

  use Membrane.Filter

  import ExMP4.Helper

  alias Membrane.{H264, H265}
  alias Xav.{Encoder, Decoder}

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
            gop_size: 16,
            profile: encoder_profile()
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

    with {:ok, frame} <- Decoder.decode(state.decoder, buffer.payload, dts: dts, pts: pts),
         packets <- Encoder.encode(state.encoder, frame) do
      buffers =
        Enum.map(
          packets,
          &%Membrane.Buffer{
            payload: &1.data,
            dts: &1.dts && timescalify(&1.dts, @dest_time_base, @original_time_base),
            pts: &1.pts && timescalify(&1.pts, @dest_time_base, @original_time_base)
          }
        )

      {[buffer: {:output, buffers}], state}
    else
      _other ->
        {[], state}
    end
  end

  # arm architecture use a precompiled ffmpeg with OpenH264 encoder which supports constrained_baseline profile
  # x264 support baseline profile
  defp encoder_profile() do
    case ExNVR.Utils.system_architecture() do
      {"arm", _os, _abi} -> :constrained_baseline
      _other -> :baseline
    end
  end
end
