defmodule ExNVR.Pipeline.Output.Socket do
  @moduledoc """
  Send snapshots through socket

  The format of the message is: |width: 2bytes|height: 2bytes|channel: 1byte|data: height * width * channel bytes|
  """

  use Membrane.Bin

  alias __MODULE__
  alias Membrane.H264

  def_options encoding: [
                spec: ExNVR.Pipelines.encoding(),
                description: "The video encoding"
              ]

  def_input_pad :input,
    demand_unit: :buffers,
    demand_mode: :auto,
    accepted_format: %H264{alignment: :au}

  @impl true
  def handle_init(_ctx, opts) do
    spec =
      [
        bin_input()
        |> child(:parser, get_parser(opts.encoding))
        |> child(:decoder, get_decoder(opts.encoding))
        |> child(:pix_format_converter, %Membrane.FFmpeg.SWScale.PixelFormatConverter{
          format: :RGB
        })
        |> child(:sink, Socket.Sink)
      ]

    {[spec: spec], %{}}
  end

  @impl true
  def handle_parent_notification(notification, _ctx, state) do
    {[notify_child: {:sink, notification}], state}
  end

  @impl true
  def handle_child_notification(notification, :sink, _ctx, state) do
    {[notify_parent: notification], state}
  end

  defp get_parser(:H264), do: %Membrane.H264.Parser{skip_until_keyframe?: true}

  defp get_decoder(:H264), do: %Membrane.H264.FFmpeg.Decoder{use_shm?: true}
end
