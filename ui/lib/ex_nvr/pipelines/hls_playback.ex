defmodule ExNVR.Pipelines.HlsPlayback do
  @moduledoc """
  A pipeline that converts recorded video into HLS playlists for streaming
  """

  use Membrane.Pipeline

  require Membrane.Logger

  alias ExNVR.Elements
  alias ExNVR.Pipeline.Output
  alias Membrane.{H264, H265}

  @call_timeout :timer.seconds(20)

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
    Logger.metadata(device_id: options[:device].id)
    Membrane.Logger.info("Start playback pipeline with options: #{inspect(options)}")

    spec = [
      child(:source, %Elements.RecordingBin{
        device: options[:device],
        start_date: options[:start_date],
        stream: options[:stream],
        duration: Membrane.Time.seconds(options[:duration])
      })
    ]

    state = %{
      directory: options[:directory],
      segment_name_prefix: options[:segment_name_prefix],
      resolution: options[:resolution],
      caller: nil
    }

    {[spec: spec], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    {[setup: :incomplete], state}
  end

  @impl true
  def handle_child_notification({:track, track}, :source, _ctx, state) do
    encoding =
      case track do
        %H264{} -> :H264
        %H265{} -> :H265
      end

    spec = [
      get_child(:source)
      |> via_out(:video)
      |> child(:realtimer, Elements.Realtimer)
      |> via_in(Pad.ref(:video, :playback),
        options: [resolution: state.resolution, encoding: encoding]
      )
      |> child(:sink, %Output.HLS{
        location: state.directory,
        segment_name_prefix: state.segment_name_prefix
      })
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification({:track_playable, _track}, :sink, _ctx, state) do
    {[reply_to: {state.caller, :ok}], %{state | caller: nil}}
  end

  @impl true
  def handle_child_notification(notification, _element, _ctx, state) do
    Membrane.Logger.warning("Received unexpected notification: #{inspect(notification)}")
    {[], state}
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
