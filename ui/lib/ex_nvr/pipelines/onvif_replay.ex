defmodule ExNVR.Pipelines.OnvifReplay do
  @moduledoc false

  use Membrane.Pipeline

  require Membrane.Logger

  defmodule TimestampFilter do
    use Membrane.Filter

    def_input_pad :input, accepted_format: _any, flow_control: :auto
    def_output_pad :output, accepted_format: _any, flow_control: :auto

    def_options start_date: [spec: DateTime.t()]

    @impl true
    def handle_init(_ctx, options) do
      {[], %{start_date: options.start_date, check?: true}}
    end

    @impl true
    def handle_buffer(:input, buffer, _ctx, %{check?: false} = state) do
      {[forward: buffer], state}
    end

    @impl true
    def handle_buffer(:input, buffer, _ctx, %{check?: true} = state) do
      if DateTime.compare(state.start_date, buffer.metadata.timestamp) == :gt do
        {[], state}
      else
        {[forward: buffer], %{state | check?: false}}
      end
    end
  end

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

    {[spec: spec], %{device: options[:device], start_date: options[:start_date]}}
  end

  @impl true
  def handle_child_notification({:new_track, id, _track}, :source, _ctx, state) do
    spec = [
      get_child(:tee)
      |> via_out(:video_output)
      |> child(:filter, %TimestampFilter{start_date: state.start_date})
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
