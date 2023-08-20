defmodule ExNVR.Pipeline.Source.RTSP do
  @moduledoc """
  An RTSP source element that reads streams from RTSP server
  """

  use Membrane.Bin

  alias ExNVR.Pipeline.Source.RTSP

  def_output_pad :output,
    demand_mode: :auto,
    demand_unit: :buffers,
    accepted_format: _any,
    availability: :on_request

  def_options stream_uri: [
                spec: binary(),
                description: """
                The uri of the resource in the RTSP server to read the streams from.
                """
              ]

  @impl true
  def handle_init(_ctx, options) do
    spec = [
      child(:source, %RTSP.Source{stream_uri: options.stream_uri})
    ]

    {[spec: spec], %{tracks: [], ssrc_to_track: %{}}}
  end

  @impl true
  def handle_child_notification({:rtsp_setup_complete, tracks}, _element, _ctx, state) do
    fmt_mapping =
      Enum.map(tracks, fn %{rtpmap: rtpmap} = track ->
        {rtpmap.payload_type, {track.encoding, rtpmap.clock_rate}}
      end)
      |> Enum.into(%{})

    ref = make_ref()

    spec = [
      get_child(:source)
      |> via_out(Pad.ref(:output, ref))
      |> via_in(Pad.ref(:rtp_input, ref))
      |> child(:rtp_session, %Membrane.RTP.SessionBin{
        fmt_mapping: fmt_mapping
      })
    ]

    {[spec: spec], %{state | tracks: tracks}}
  end

  @impl true
  def handle_child_notification(:connection_lost, :source, _ctx, state) do
    {[remove_child: :rtp_session, remove_child: Map.keys(state.ssrc_to_track)],
     %{state | ssrc_to_track: %{}, tracks: []}}
  end

  @impl true
  def handle_child_notification(
        {:new_rtp_stream, ssrc, pt, _extensions},
        :rtp_session,
        _ctx,
        state
      ) do
    track = Enum.find(state.tracks, fn track -> track.rtpmap.payload_type == pt end)
    ssrc_to_track = Map.put(state.ssrc_to_track, ssrc, track)
    {[notify_parent: {:new_track, ssrc, track}], %{state | ssrc_to_track: ssrc_to_track}}
  end

  @impl true
  def handle_child_notification(_notification, _element, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, ssrc) = pad, _ctx, state) do
    track = Map.fetch!(state.ssrc_to_track, ssrc)
    spec = [get_specs(track, ssrc) |> bin_output(pad)]
    {[spec: {spec, group: ssrc}], state}
  end

  defp get_specs(%{type: :video} = track, ssrc) do
    sps = track.fmtp.sprop_parameter_sets.sps
    pps = track.fmtp.sprop_parameter_sets.pps

    get_child(:rtp_session)
    |> via_out(Pad.ref(:output, ssrc), options: [depayloader: get_depayloader(track)])
    |> child({:rtp_parser, ssrc}, %Membrane.H264.Parser{sps: sps, pps: pps})
  end

  defp get_specs(%{type: :audio} = track, ssrc) do
    get_child(:rtp_session)
    |> via_out(Pad.ref(:output, ssrc), options: [depayloader: get_depayloader(track)])
  end

  defp get_specs(%{type: :application} = track, ssrc) do
    get_child(:rtp_session)
    |> via_out(Pad.ref(:output, ssrc), options: [depayloader: get_depayloader(track)])
  end

  defp get_depayloader(%{encoding: :H264}), do: Membrane.RTP.H264.Depayloader
  defp get_depayloader(_track), do: nil
end
