defmodule ExNVR.Pipelines.Snapshot do
  @moduledoc """
  Pipeline responsible for retrieving a snapshot from an MP4 file
  """

  use Membrane.Pipeline

  alias Membrane.H264
  alias ExNVR.Elements
  alias ExNVR.Elements.MP4

  def start_link(options) do
    Pipeline.start_link(__MODULE__, options)
  end

  def start(options) do
    Pipeline.start_link(__MODULE__, options)
  end

  @impl true
  def handle_init(_ctx, options) do
    allow_option =
      case options[:method] do
        :precise -> :last
        _ -> :first
      end

    spec = [
      child(:source, %MP4.Depayloader{
        device_id: options[:device_id],
        start_date: options[:date],
        end_date: options[:date]
      })
      |> child(:parser, H264.Parser)
      |> child(:decoder, H264.FFmpeg.Decoder)
      |> child(:scissor, %Elements.FirstOrLast{allow: allow_option})
      |> child(:sink, %Elements.Image{
        destination: options[:destination],
        format: options[:format] || :jpeg
      })
    ]

    {[spec: spec, playback: :playing], %{}}
  end

  @impl true
  def handle_element_end_of_stream(:sink, _pad, _ctx, state) do
    {[terminate: true], state}
  end

  @impl true
  def handle_element_end_of_stream(_element, _pad, _ctx, state) do
    {[], state}
  end
end
