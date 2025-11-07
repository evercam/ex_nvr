defmodule ExNVR.Pipeline.Output.ObjectDetection.Decoder do
  @moduledoc false

  use Membrane.Filter

  require Membrane.Logger

  import ExNVR.MediaUtils, only: [to_annexb: 1]

  alias Membrane.{H264, H265, RawVideo}

  def_input_pad :input, accepted_format: any_of(%H264{}, %H265{})
  def_output_pad :output, accepted_format: %RawVideo{}

  @impl true
  def handle_init(_ctx, _options) do
    {[], %{decoder: nil}}
  end

  @impl true
  def handle_stream_format(:input, stream_format, %{pads: %{input: %{stream_format: nil}}}, state) do
    codec =
      cond do
        is_struct(stream_format, H264) -> :h264
        is_struct(stream_format, H265) -> :hevc
      end

    decoder =
      ExNVR.AV.Decoder.new(codec, out_width: 640, out_height: 640, out_format: :rgb24, pad: true)

    {[
       stream_format:
         {:output,
          %RawVideo{
            height: 640,
            width: 640,
            aligned: true,
            pixel_format: :I420,
            framerate: 0
          }}
     ], %{state | decoder: decoder}}
  end

  @impl true
  def handle_stream_format(:input, _stream_format, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    buffers =
      state.decoder
      |> ExNVR.AV.Decoder.decode(to_annexb(buffer.payload), pts: buffer.pts)
      |> Enum.map(fn frame ->
        %Membrane.Buffer{pts: frame.pts, payload: frame.data, metadata: buffer.metadata}
      end)

    {[buffer: {:output, buffers}], state}
  end
end
