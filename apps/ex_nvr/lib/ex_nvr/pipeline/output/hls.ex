defmodule ExNVR.Pipeline.Output.HLS do
  @moduledoc """
  Output element that create HLS playlists from audio/video
  """

  use Membrane.Bin

  alias Membrane.{H264, ResourceGuard}
  alias Membrane.HTTPAdaptiveStream.{SinkBin, Storages}

  @segment_duration Membrane.Time.seconds(5)

  def_input_pad :video,
    demand_unit: :buffers,
    demand_mode: :auto,
    accepted_format: %H264{alignment: :au},
    availability: :on_request,
    options: [
      resolution: [
        spec: non_neg_integer() | nil,
        default: nil,
        description: """
        Transcode the video to the provided resolution.

        The resolution denotes the height of the video. e.g. 720p
        """
      ]
    ]

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
      child(:sink, %SinkBin{
        manifest_module: Membrane.HTTPAdaptiveStream.HLS,
        storage: %Storages.FileStorage{directory: options.location},
        mode: :live,
        segment_naming_fun: fn track ->
          "#{segment_prefix}_#{track.id}_#{track.next_segment_id}"
        end
      })
    ]

    {[spec: spec], %{segment_prefix: segment_prefix}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:video, ref) = pad, ctx, state) do
    spec = [
      bin_input(pad)
      |> add_transcoding_spec(ref, ctx.options[:resolution])
      |> via_in(Pad.ref(:input, ref),
        options: [
          encoding: :H264,
          track_name: track_name(state.segment_prefix, ref),
          segment_duration: @segment_duration
        ]
      )
      |> get_child(:sink)
    ]

    {[spec: {spec, group: ref}], state}
  end

  @impl true
  def handle_pad_removed(Pad.ref(:video, ref), _ctx, state) do
    {[remove_children: ref], state}
  end

  @impl true
  def handle_child_notification({:track_playable, track_id}, :sink, _ctx, state) do
    {[notify_parent: {:track_playable, track_id}], state}
  end

  @impl true
  def handle_child_notification(_notification, _element, _ctx, state) do
    {[], state}
  end

  defp add_transcoding_spec(link_builder, _ref, nil), do: link_builder

  defp add_transcoding_spec(link_builder, ref, resolution) do
    link_builder
    |> child({:decoder, ref}, Membrane.H264.FFmpeg.Decoder)
    |> child({:scaler, ref}, %Membrane.FFmpeg.SWScale.Scaler{output_height: resolution})
    |> child({:encoder, ref}, %Membrane.H264.FFmpeg.Encoder{
      profile: :baseline,
      tune: :zerolatency
    })
    |> child({:parser, ref}, Membrane.H264.Parser)
  end

  defp track_name(prefix, ref), do: "#{prefix}_#{ref}"
end
