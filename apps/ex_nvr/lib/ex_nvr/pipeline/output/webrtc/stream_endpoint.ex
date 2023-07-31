defmodule ExNVR.Pipeline.Output.WebRTC.StreamEndpoint do
  @moduledoc """
  An RTC endpoint that receives NAL units from the main pipeline.
  """

  require Logger
  use Membrane.Bin

  require Membrane.Logger

  alias ExNVR.Pipeline.Output
  alias Membrane.RTC.Engine.Endpoint.WebRTC.TrackSender
  alias Membrane.RTC.Engine.Track
  alias Membrane.RTP

  def_output_pad :output,
    demand_unit: :buffers,
    flow_control: :auto,
    accepted_format: RTP,
    availability: :on_request

  def_options rtc_engine: [
                spec: pid(),
                default: nil
              ]

  @impl true
  def handle_init(_ctx, _options) do
    {[notify_parent: :ready], %{track: nil}}
  end

  @impl true
  def handle_parent_notification({:media_track, media_track}, ctx, state) do
    {:endpoint, endpoint_id} = ctx.name

    track =
      Track.new(
        media_track.type,
        Track.stream_id(),
        endpoint_id,
        media_track.codec,
        media_track.clock_rate,
        %{media_track.payload_type => {"#{media_track.codec}", media_track.clock_rate}},
        ctx: %{
          rtpmap: %{
            payload_type: media_track.payload_type,
            clock_rate: media_track.clock_rate,
            encoding: "#{media_track.codec}"
          }
        }
      )

    {[
       notify_parent: {:publish, {:new_tracks, [track]}},
       notify_parent: {:track_ready, track.id, :high, track.encoding}
     ], %{state | track: track}}
  end

  @impl true
  def handle_parent_notification(:remove_track, _ctx, state) do
    Logger.warning("Remove track notification received, removed track: #{state.track.id}")
    {[notify_parent: {:publish, {:removed_tracks, [state.track]}}], %{state | track: nil}}
  end

  @impl true
  def handle_parent_notification(_notification, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, {track_id, :high}) = pad, _ctx, state)
      when track_id == state.track.id do
    spec = [
      child(:source, Output.WebRTC.Source)
      |> child(:parser, %Membrane.H264.FFmpeg.Parser{alignment: :nal})
      |> child(:rtp_payloader, %Membrane.RTP.PayloaderBin{
        payloader: Membrane.RTP.H264.Payloader,
        clock_rate: state.track.clock_rate,
        payload_type: 96,
        ssrc: :rand.uniform(1_000_000)
      })
      |> via_in(Pad.ref(:input, {track_id, :high}))
      |> child(
        {:track_sender, track_id},
        %TrackSender{
          track: state.track,
          variant_bitrates: %{},
          is_keyframe_fun: fn buf, :H264 ->
            Membrane.RTP.H264.Utils.is_keyframe(buf.payload, :idr)
          end
        }
      )
      |> via_out(pad)
      |> bin_output(pad)
    ]

    {[spec: {spec, group: track_id}], state}
  end

  @impl true
  def handle_pad_removed(Pad.ref(:output, {track_id, :high}), _ctx, state) do
    {[remove_child: track_id], state}
  end

  @impl true
  def handle_child_notification({:pid, pid}, :source, _ctx, state) do
    {[notify_parent: {:forward_to_parent, {:source_pid, pid}}], state}
  end

  @impl true
  def handle_child_notification(_message, _element, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_info({:stream, message}, _ctx, state) do
    {[notify_child: {:source, message}], state}
  end

  @impl true
  def handle_info(_message, _ctx, state) do
    {[], state}
  end
end
