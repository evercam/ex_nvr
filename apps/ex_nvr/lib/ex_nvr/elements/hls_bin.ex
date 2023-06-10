defmodule ExNVR.Elements.HLSBin do
  @moduledoc """
  An hls element that receive an H264 stream and create playlists.

  This element may transcode the stream to different resolutions to support multiple clients
  """

  use Membrane.Bin

  alias Membrane.{H264, ResourceGuard}
  alias Membrane.HTTPAdaptiveStream.{Sink, Storages}

  def_input_pad :input,
    demand_unit: :buffers,
    demand_mode: :auto,
    accepted_format: %H264{alignment: :au},
    availability: :on_request

  def_options location: [
                spec: Path.t(),
                description: """
                Directory where to save the generated files
                """
              ],
              segment_name_prefix: [
                spec: binary(),
                description: """
                A prefix that will be used to generate names for the segments.

                It'll be used as a replacement for the lack of support of query params
                in the segments names.
                """
              ]

  @impl true
  def handle_init(ctx, %__MODULE__{} = options) do
    segment_prefix = options.segment_name_prefix

    File.mkdir_p!(options.location)

    ResourceGuard.register(ctx.resource_guard, fn ->
      File.rm_rf!(options.location)
    end)

    spec = [
      child(:sink, %Sink{
        manifest_config: %Sink.ManifestConfig{
          name: "index",
          module: Membrane.HTTPAdaptiveStream.HLS
        },
        track_config: %Sink.TrackConfig{
          mode: :live,
          target_window_duration: Membrane.Time.seconds(60),
          segment_naming_fun: fn track ->
            "#{segment_prefix}_#{track.id}_#{track.next_segment_id}"
          end
        },
        storage: %Storages.FileStorage{directory: options.location}
      })
    ]

    {[spec: spec], %{segment_prefix: segment_prefix}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, ref) = pad, _ctx, state) do
    spec = [
      bin_input(pad)
      |> child({:payloader, ref}, Membrane.MP4.Payloader.H264)
      |> child({:muxer, ref}, Membrane.MP4.Muxer.CMAF)
      |> via_in(pad,
        options: [
          track_name: "#{state.segment_prefix}_#{ref}",
          segment_duration: Membrane.Time.seconds(5)
        ]
      )
      |> get_child(:sink)
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification({:track_playable, track_id}, :sink, _ctx, state) do
    {[notify_parent: {:track_playable, track_id}], state}
  end

  @impl true
  def handle_child_notification(_notification, _element, _ctx, state) do
    {[], state}
  end
end
