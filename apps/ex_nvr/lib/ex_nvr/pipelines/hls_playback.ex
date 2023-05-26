defmodule ExNVR.Pipelines.HlsPlayback do
  @moduledoc """
  A pipeline that converts recorded video into HLS playlists for streaming
  """

  use Membrane.Pipeline

  alias ExNVR.Elements.MP4

  @call_timeout 60_000

  def start_link(opts) do
    Pipeline.start_link(__MODULE__, opts, name: opts[:name])
  end

  def start(opts) do
    Pipeline.start(__MODULE__, opts, name: opts[:name])
  end

  def start_streaming(pipeline) do
    Pipeline.call(pipeline, :start_streaming, @call_timeout)
  end

  def stop_streaming(pipeline) do
    Pipeline.call(pipeline, :stop_streaming)
  end

  @impl true
  def handle_init(ctx, options) do
    Membrane.ResourceGuard.register(ctx.resource_guard, fn ->
      File.rm_rf!(options[:directory])
    end)

    spec = [
      child(:source, %MP4.Depayloader{start_date: options[:start_date]})
      |> child(:realtimer, Membrane.Realtimer)
      |> child(:parser, %Membrane.H264.Parser{framerate: {0, 0}})
      |> child(:decoder, Membrane.H264.FFmpeg.Decoder)
      |> child(:scaler, %Membrane.FFmpeg.SWScale.Scaler{output_width: 1280, output_height: 720})
      |> child(:encoder, %Membrane.H264.FFmpeg.Encoder{
        profile: :baseline,
        gop_size: 50
      })
      |> child(:parser2, %Membrane.H264.FFmpeg.Parser{attach_nalus?: true})
      |> via_in(Pad.ref(:input, "#{options[:segment_name_prefix]}_720p"),
        options: [
          encoding: :H264,
          segment_duration: Membrane.Time.seconds(5)
        ]
      )
      |> child(:hls, %Membrane.HTTPAdaptiveStream.SinkBin{
        manifest_module: Membrane.HTTPAdaptiveStream.HLS,
        mode: :live,
        storage: %Membrane.HTTPAdaptiveStream.Storages.FileStorage{
          directory: options[:directory]
        },
        target_window_duration: Membrane.Time.seconds(60),
        segment_naming_fun: fn track ->
          "#{options[:segment_name_prefix]}_#{track.id}_#{track.next_segment_id}"
        end
      })
    ]

    {[spec: spec], %{caller: nil}}
  end

  @impl true
  def handle_child_notification({:track_playable, _track}, :hls, _ctx, state) do
    {[reply_to: {state.caller, :ok}], %{state | caller: nil}}
  end

  @impl true
  def handle_child_notification(_notification, _element, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_call(:start_streaming, %{from: from}, state) do
    {[playback: :playing], %{state | caller: from}}
  end

  @impl true
  def handle_call(:stop_streaming, _ctx, state) do
    {[reply: :ok, terminate: :shutdown], state}
  end
end
