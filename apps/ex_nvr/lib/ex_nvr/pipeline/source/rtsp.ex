defmodule ExNVR.Pipeline.Source.RTSP do
  @moduledoc """
  An RTSP source element that reads streams from RTSP server
  """

  use Membrane.Bin

  require Membrane.Logger

  alias ExNVR.Media.Track
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
              ],
              stream_types: [
                spec: [:video | :audio | :application],
                default: [:video],
                description: """
                The type of streams to read from the RTSP server.
                Defaults to read only video streams
                """
              ]

  @impl true
  def handle_init(_ctx, options) do
    spec = [
      child(:source, %RTSP.Source{
        stream_uri: options.stream_uri,
        stream_types: options.stream_types
      })
    ]

    {[spec: spec], %{tracks: [], ssrc_to_track: %{}}}
  end

  @impl true
  def handle_child_notification({:rtsp_setup_complete, tracks}, _element, _ctx, state) do
    Membrane.Logger.info("Received rtsp setup complete notification with #{inspect(tracks)}")

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
  def handle_child_notification(:connection_lost, :source, ctx, state) do
    Membrane.Logger.info("Connection lost to RTSP server")

    ssrcs = Map.keys(state.ssrc_to_track)

    childs =
      ctx.children
      |> Map.keys()
      |> Enum.filter(fn
        {_, ssrc} -> ssrc in ssrcs
        :rtp_session -> true
        _other -> false
      end)

    {[remove_child: childs], %{state | ssrc_to_track: %{}, tracks: []}}
  end

  @impl true
  def handle_child_notification(
        {:new_rtp_stream, ssrc, pt, _extensions},
        :rtp_session,
        _ctx,
        state
      ) do
    if track = Enum.find(state.tracks, fn track -> track.rtpmap.payload_type == pt end) do
      ssrc_to_track = Map.put(state.ssrc_to_track, ssrc, track)
      {[notify_parent: {:new_track, ssrc, track}], %{state | ssrc_to_track: ssrc_to_track}}
    else
      {[], state}
    end
  end

  @impl true
  def handle_child_notification(_notification, _element, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, ssrc) = pad, _ctx, state) do
    track = Map.fetch!(state.ssrc_to_track, ssrc)
    spec = [get_specs(track, ssrc) |> bin_output(pad)]
    {[spec: spec], state}
  end

  defp get_specs(%Track{type: :video} = track, ssrc) do
    sps = track.fmtp.sprop_parameter_sets.sps
    pps = track.fmtp.sprop_parameter_sets.pps

    get_child(:rtp_session)
    |> via_out(Pad.ref(:output, ssrc), options: [depayloader: get_depayloader(track)])
    |> child({:rtp_parser, ssrc}, %Membrane.H264.Parser{sps: sps, pps: pps})
  end

  defp get_specs(%Track{type: type}, _ssrc) do
    raise "Support for tracks for type '#{type}' not yet implemented"
  end

  defp get_depayloader(%{encoding: :H264}), do: Membrane.RTP.H264.Depayloader
  defp get_depayloader(_track), do: nil
end
