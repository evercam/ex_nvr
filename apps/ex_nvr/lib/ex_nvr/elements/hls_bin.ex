defmodule ExNVR.Elements.HLSBin do
  @moduledoc """
  A hls element that receive an H264 stream and create playlists.

  This element may transcode the stream to different resolutions to support multiple clients
  """

  use Membrane.Bin

  alias Membrane.H264
  alias Membrane.HTTPAdaptiveStream.Sink

  def_input_pad :input,
    demand_unit: :buffers,
    demand_mode: :auto,
    accepted_format: %H264{alignment: :au},
    availability: :always

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
  def handle_init(_ctx, %__MODULE__{} = options) do
    spec = [
      bin_input(:input)
      |> child(:hls_forwarder, ExNVR.Elements.HLS.Forwarder)
      |> child(:hls_payloader, Membrane.MP4.Payloader.H264)
      |> child(:hls_muxer, Membrane.MP4.Muxer.CMAF)
      |> via_in(Pad.ref(:input, make_ref()),
        options: [
          segment_duration: Membrane.Time.seconds(5)
        ]
      )
      |> child(:hls, %Sink{
        manifest_config: %{
          name: "index",
          module: Membrane.HTTPAdaptiveStream.HLS
        },
        storage: %Membrane.HTTPAdaptiveStream.Storages.FileStorage{
          directory: options.location
        },
        track_config: %Sink.TrackConfig{
          target_window_duration: Membrane.Time.seconds(60),
          mode: :live,
          segment_naming_fun: fn track ->
            "#{options.segment_name_prefix}_#{track.next_segment_id}"
          end
        }
      })
    ]

    {[spec: spec], %{}}
  end

  @impl true
  def handle_child_notification({:track_playable, _pad_id} = notification, :hls, _ctx, state) do
    {[notify_parent: notification], state}
  end
end
