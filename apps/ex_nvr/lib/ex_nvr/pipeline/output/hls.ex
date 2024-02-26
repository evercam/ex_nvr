defmodule ExNVR.Pipeline.Output.HLS do
  @moduledoc """
  Output element that create HLS playlists from audio/video
  """

  use Membrane.Bin

  alias Membrane.{H264, H265, ResourceGuard}
  alias Membrane.HTTPAdaptiveStream.{SinkBin, Storages}

  @segment_duration Membrane.Time.seconds(5)

  def_input_pad :video,
    accepted_format: any_of(%H264{alignment: :au}, %H265{alignment: :au}),
    availability: :on_request,
    options: [
      resolution: [
        spec: non_neg_integer() | nil,
        default: nil,
        description: """
        Transcode the video to the provided resolution.

        The resolution denotes the height of the video. e.g. 720p
        """
      ],
      encoding: [
        spec: atom(),
        description: "The encoding of the video stream"
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
      |> add_transcoding_spec(ctx.pad_options[:encoding], ref, ctx.pad_options[:resolution])
      |> via_in(Pad.ref(:input, ref),
        options: [
          encoding: ctx.pad_options[:encoding],
          track_name: track_name(state.segment_prefix, ref),
          segment_duration: @segment_duration
        ]
      )
      |> get_child(:sink)
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_pad_removed(Pad.ref(:video, ref), ctx, state) do
    childs_to_remove =
      ctx.children
      |> Map.keys()
      |> Enum.filter(fn
        {_name, ^ref} -> true
        _other -> false
      end)

    {[remove_children: childs_to_remove], state}
  end

  @impl true
  def handle_child_notification({:track_playable, track_id}, :sink, _ctx, state) do
    {[notify_parent: {:track_playable, track_id}], state}
  end

  @impl true
  def handle_child_notification(_notification, _element, _ctx, state) do
    {[], state}
  end

  defp add_transcoding_spec(link_builder, _encoding, _ref, nil), do: link_builder

  defp add_transcoding_spec(link_builder, encoding, ref, resolution) do
    link_builder
    |> child({:decoder, ref}, get_decoder(encoding))
    |> child({:scaler, ref}, %Membrane.FFmpeg.SWScale.Scaler{output_height: resolution})
    |> child({:encoder, ref}, %Membrane.H264.FFmpeg.Encoder{
      profile: :baseline,
      tune: :zerolatency,
      gop_size: 50
    })
    |> child({:parser, ref}, Membrane.H264.Parser)
  end

  defp track_name(prefix, ref), do: "#{prefix}_#{ref}"

  defp get_decoder(:H264), do: %Membrane.H264.FFmpeg.Decoder{use_shm?: true}
  defp get_decoder(:H265), do: %Membrane.H265.FFmpeg.Decoder{use_shm?: true}
end
