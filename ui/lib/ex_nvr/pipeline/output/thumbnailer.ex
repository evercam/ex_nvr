defmodule ExNVR.Pipeline.Output.Thumbnailer do
  @moduledoc """
  Generate thumbnails at regular interval. The element will only decode keyframes at the expense of exact timestamps.
  """

  use Membrane.Sink

  require ExNVR.Utils
  require Membrane.Logger

  import ExNVR.MediaUtils, only: [to_annexb: 1]

  alias ExNVR.AV.Decoder
  alias Membrane.{Buffer, H264, H265}

  def_input_pad :input,
    accepted_format:
      any_of(
        %H264{alignment: :au},
        %H265{alignment: :au}
      )

  def_options interval: [
                spec: integer(),
                default: 10,
                description: """
                The rate of thumbnails generation.
                Defaults to one thumbnail per 10 seconds.
                """
              ],
              thumbnail_width: [
                spec: non_neg_integer(),
                default: 320,
                description: "The width of the generated thumbnail"
              ],
              dest: [
                spec: Path.t(),
                description: "The destination folder where the thumbnails will be stored"
              ]

  @impl true
  def handle_init(_ctx, options) do
    state =
      options
      |> Map.from_struct()
      |> Map.merge(%{
        thumbnail_height: nil,
        decoder: nil,
        last_buffer_pts: nil
      })

    Process.set_label(:thumbnailer)

    {[], state}
  end

  @impl true
  def handle_stream_format(:input, format, ctx, state) do
    old_stream_format = ctx.pads.input.stream_format

    if is_nil(old_stream_format) or old_stream_format != format do
      codec = if is_struct(format, H264), do: :h264, else: :hevc

      out_height = div(state.thumbnail_width * format.height, format.width)
      out_height = out_height - rem(out_height, 2)

      decoder = Decoder.new(codec, out_height: out_height, out_width: state.thumbnail_width)

      {[], %{state | thumbnail_height: out_height, decoder: decoder}}
    else
      {[], state}
    end
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) when ExNVR.Utils.keyframe(buffer) do
    last_pts = state.last_buffer_pts || Buffer.get_dts_or_pts(buffer)
    interval = Membrane.Time.as_seconds(Buffer.get_dts_or_pts(buffer) - last_pts, :round)

    if is_nil(state.last_buffer_pts) or interval >= state.interval,
      do: do_decode(buffer, state),
      else: {[], state}
  end

  @impl true
  def handle_buffer(:input, _buffer, _ctx, state), do: {[], state}

  defp do_decode(buffer, state) do
    with [decoded] <- Decoder.decode(state.decoder, to_annexb(buffer.payload)),
         jpeg_image <- ExNVR.AV.VideoProcessor.encode_to_jpeg(decoded),
         :ok <- File.write(image_path(state.dest, buffer), jpeg_image) do
      {[], %{state | last_buffer_pts: buffer.pts}}
    else
      error ->
        Membrane.Logger.error("Failed to generate thumbnail: #{inspect(error)}")
        {[], state}
    end
  end

  defp image_path(dest_folder, buffer) do
    filename =
      if Application.get_env(:ex_nvr, :env) == :test,
        do: "#{Membrane.Buffer.get_dts_or_pts(buffer)}.jpg",
        else: "#{DateTime.utc_now() |> DateTime.to_unix()}.jpg"

    Path.join(dest_folder, filename)
  end
end
