defmodule ExNVR.Pipelines.HlsPlayback do
  @moduledoc """
  A pipeline that converts recorded video into HLS playlists for streaming
  """

  use Membrane.Pipeline

  require Membrane.Logger

  alias ExNVR.Elements.MP4
  alias ExNVR.Pipeline.Output

  @call_timeout 60_000

  @spec start_link(Keyword.t()) :: Pipeline.on_start()
  def start_link(opts) do
    Pipeline.start_link(__MODULE__, opts, name: opts[:name])
  end

  @spec start(Keyword.t()) :: Pipeline.on_start()
  def start(opts) do
    Pipeline.start(__MODULE__, opts, name: opts[:name])
  end

  @spec start_streaming(pid() | atom()) :: :ok
  def start_streaming(pipeline) do
    Membrane.Logger.info("Start playback")
    Pipeline.call(pipeline, :start_streaming, @call_timeout)
  end

  @spec stop_streaming(pid() | atom()) :: :ok
  def stop_streaming(pipeline) do
    Pipeline.call(pipeline, :stop_streaming)
  end

  @impl true
  def handle_init(_ctx, options) do
    Logger.metadata(device_id: options[:device_id])
    Membrane.Logger.info("Start playback pipeline with options: #{inspect(options)}")

    spec = [
      child(:source, %MP4.Depayloader{
        device_id: options[:device_id],
        start_date: options[:start_date]
      })
      |> child(:realtimer, Membrane.Realtimer)
      |> child(:parser, %Membrane.H264.Parser{framerate: {0, 0}})
      |> via_in(Pad.ref(:video, :playback), options: [resolution: options[:resolution]])
      |> child(:sink, %Output.HLS{
        location: options[:directory],
        segment_name_prefix: options[:segment_name_prefix]
      })
    ]

    {[spec: spec], %{caller: nil}}
  end

  @impl true
  def handle_setup(_ctx, state) do
    {[setup: :incomplete], state}
  end

  @impl true
  def handle_child_notification({:track_playable, _track}, :sink, _ctx, state) do
    {[reply_to: {state.caller, :ok}], %{state | caller: nil}}
  end

  @impl true
  def handle_call(:start_streaming, %{from: from}, state) do
    {[setup: :complete], %{state | caller: from}}
  end

  @impl true
  def handle_call(:stop_streaming, _ctx, state) do
    Membrane.Logger.info("Stop playback")
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
