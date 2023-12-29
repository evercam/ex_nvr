defmodule ExNVR.Pipeline.Output.Thumbnailer do
  @moduledoc """
  Generate thumbnails at regular interval. The element will only decode keyframes at the expense of exact timestamps.
  """

  use Membrane.Bin

  alias __MODULE__.{KeyFrameSelector, Sink}
  alias Membrane.{FFmpeg, H264, H265}

  def_input_pad :input,
    flow_control: :auto,
    accepted_format:
      any_of(
        %H264{alignment: :au},
        %H265{alignment: :au}
      )

  def_options interval: [
                spec: Membrane.Time.t(),
                default: Membrane.Time.seconds(10),
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
              ],
              encoding: [
                spec: :H264 | :H265,
                description: "The codec used to compress the frames"
              ]

  @impl true
  def handle_init(_ctx, options) do
    File.mkdir_p!(options.dest)

    spec = [
      bin_input()
      |> child(:key_frame_selector, %KeyFrameSelector{interval: options.interval})
      |> child(:decoder, get_decoder(options.encoding))
      |> child(:scaler, %FFmpeg.SWScale.Scaler{
        output_width: options.thumbnail_width,
        use_shm?: true
      })
      |> child(:image_encoder, Turbojpeg.Filter)
      |> child(:sink, %Sink{dest: options.dest})
    ]

    {[spec: spec], %{}}
  end

  defp get_decoder(:H264), do: %H264.FFmpeg.Decoder{use_shm?: true}
  defp get_decoder(:H265), do: %H265.FFmpeg.Decoder{use_shm?: true}
end
