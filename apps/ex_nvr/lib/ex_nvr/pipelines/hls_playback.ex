defmodule ExNVR.Pipelines.HlsPlayback do
  @moduledoc """
  A pipeline that converts recorded video into HLS playlists for streaming
  """

  use Membrane.Pipeline

  alias ExNVR.Elements.MP4
  alias Membrane.HTTPAdaptiveStream.{Sink, Storages}

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
    File.mkdir_p!(options[:directory])

    Membrane.ResourceGuard.register(ctx.resource_guard, fn ->
      File.rm_rf!(options[:directory])
    end)

    spec = [
      child(:source, %MP4.Depayloader{
        device_id: options[:device_id],
        start_date: options[:start_date]
      })
      |> child(:realtimer, Membrane.Realtimer)
      |> child(:parser, %Membrane.H264.Parser{framerate: {0, 0}})
      |> child(:hls_payloader, Membrane.MP4.Payloader.H264)
      |> child(:hls_muxer, Membrane.MP4.Muxer.CMAF)
      |> via_in(Pad.ref(:input, "playback"),
        options: [
          track_name: "#{options[:segment_name_prefix]}_org",
          segment_duration: Membrane.Time.seconds(5)
        ]
      )
      |> child(:hls, %Sink{
        manifest_config: %Sink.ManifestConfig{
          name: "index",
          module: Membrane.HTTPAdaptiveStream.HLS
        },
        track_config: %Sink.TrackConfig{
          mode: :live,
          target_window_duration: Membrane.Time.seconds(60),
          segment_naming_fun: fn track ->
            "#{options[:segment_name_prefix]}_#{track.id}_#{track.next_segment_id}"
          end
        },
        storage: %Storages.FileStorage{directory: options[:directory]}
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

  def child_spec(arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [arg]},
      restart: :temporary,
      type: :supervisor
    }
  end
end
