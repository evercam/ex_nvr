defmodule ExNVR.Pipelines.OnvifReplay do
  @moduledoc false

  use Membrane.Pipeline

  require Membrane.Logger

  def start_link(opts) do
    Pipeline.start_link(__MODULE__, opts)
  end

  def start(opts) do
    Pipeline.start(__MODULE__, opts)
  end

  @impl true
  def handle_init(_ctx, options) do
    Membrane.Logger.info(
      "[OnvifReplay] Start onvif replay pipeline for #{options[:device].id} from #{options[:start_date]} to #{options[:end_date]}"
    )

    spec =
      [
        {child(:source, %ExNVR.RTSP.Source{
          stream_uri: options[:stream_uri],
          allowed_media_types: [:video],
          onvif_replay: true,
          start_date: options[:start_date],
          end_date: options[:end_date]
        }), group: :source_group, crash_group_mode: :temporary},
        child(:tee, ExNVR.Elements.FunnelTee)
      ]

    {[spec: spec], %{device: options[:device]}}
  end

  @impl true
  def handle_child_notification({:new_track, id, _track}, :source, _ctx, state) do
    spec = [
      get_child(:tee)
      |> via_out(:video_output)
      |> child(:storage, %ExNVR.Pipeline.Output.Storage{
        device: state.device,
        onvif_replay: true,
        stream: :high,
        correct_timestamp: false
      }),
      get_child(:source)
      |> via_out(Pad.ref(:output, id))
      |> via_in(Pad.ref(:video, make_ref()))
      |> get_child(:tee)
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification(_notification, _element, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_crash_group_down(:source_group, _ctx, state) do
    {[terminate: :normal], state}
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
