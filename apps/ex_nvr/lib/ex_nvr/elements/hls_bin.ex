defmodule ExNVR.Elements.HLSBin do
  @moduledoc """
  An hls element that receive an H264 stream and create playlists.

  This element may transcode the stream to different resolutions to support multiple clients
  """

  use Membrane.Bin

  alias Membrane.H264
  alias Membrane.HTTPAdaptiveStream.Sink

  @high_quality "1080x720"
  @low_quality "640x480"

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
      |> child(:hls_decoder, Membrane.H264.FFmpeg.Decoder)
      |> child(:hls_tee, Membrane.Tee.Master),
      child(:hls, %Sink{
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
            "#{options.segment_name_prefix}_#{track.id}_#{track.next_segment_id}"
          end
        }
      })
    ]

    spec = maybe_add_high_quality_elements(spec)
    spec = maybe_add_low_quality_elements(spec)

    {[spec: spec], %{}}
  end

  @impl true
  def handle_child_notification({:track_playable, _pad_id} = notification, :hls, _ctx, state) do
    {[notify_parent: notification], state}
  end

  defp maybe_add_high_quality_elements(spec) do
    spec ++
      [
        get_child(:hls_tee)
        |> via_out(:master)
        |> child(:hls_high_rescaler, %Membrane.FFmpeg.SWScale.Scaler{
          output_width: 1080,
          output_height: 720
        })
        |> child(:hls_high_encoder, %Membrane.H264.FFmpeg.Encoder{
          profile: :baseline,
          gop_size: 50
        })
        |> child(:hls_high_parser, %Membrane.H264.FFmpeg.Parser{
          alignment: :au,
          attach_nalus?: true
        })
        |> child(:hls_high_payloader, Membrane.MP4.Payloader.H264)
        |> child(:hls_high_muxer, Membrane.MP4.Muxer.CMAF)
        |> via_in(Pad.ref(:input, @high_quality),
          options: [segment_duration: Membrane.Time.seconds(5)]
        )
        |> get_child(:hls)
      ]
  end

  defp maybe_add_low_quality_elements(spec) do
    spec ++
      [
        get_child(:hls_tee)
        |> via_out(:copy)
        |> child(:hls_low_rescaler, %Membrane.FFmpeg.SWScale.Scaler{
          output_width: 640,
          output_height: 480
        })
        |> child(:hls_low_encoder, %Membrane.H264.FFmpeg.Encoder{
          profile: :baseline,
          gop_size: 50
        })
        |> child(:hls_low_parser, %Membrane.H264.FFmpeg.Parser{
          alignment: :au,
          attach_nalus?: true
        })
        |> child(:hls_low_payloader, Membrane.MP4.Payloader.H264)
        |> child(:hls_low_muxer, Membrane.MP4.Muxer.CMAF)
        |> via_in(Pad.ref(:input, @low_quality),
          options: [segment_duration: Membrane.Time.seconds(5)]
        )
        |> get_child(:hls)
      ]
  end
end
