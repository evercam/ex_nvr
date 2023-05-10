defmodule ExNVR.RTSP.Source do
  @moduledoc """
  Element that starts an RTSP session and read packets from the same connection
  """

  use Membrane.Source
  use Bunch.Access

  require Membrane.Logger

  alias ExNVR.RTSP.ConnectionManager
  alias Membrane.{Buffer, RemoteStream}

  @max_reconnect_attempts 3
  @reconnect_delay 3_000

  def_options stream_uri: [
                spec: binary(),
                default: nil,
                description: "A RTSP URI from where to read the stream"
              ]

  def_output_pad :output, accepted_format: %RemoteStream{type: :packetized}, mode: :push

  @impl true
  def handle_init(_context, %__MODULE__{} = options) do
    {[], %{stream_uri: options[:stream_uri], connection_manager: nil}}
  end

  @impl true
  def handle_setup(_context, state) do
    {:ok, connection_manager} =
      ConnectionManager.start_link(
        endpoint: self(),
        stream_uri: state[:stream_uri],
        max_reconnect_attempts: @max_reconnect_attempts,
        reconnect_delay: @reconnect_delay
      )

    {[], %{state | connection_manager: connection_manager}}
  end

  @impl true
  def handle_playing(_context, state) do
    {[stream_format: {:output, %RemoteStream{type: :packetized}}], state}
  end

  @impl true
  def handle_info({:rtsp_setup_complete, _setup} = msg, _context, state) do
    {[notify_parent: msg], state}
  end

  @impl true
  def handle_info({:media_packet, packet}, %{playback: :playing}, state) do
    metadata = %{arrival_ts: Membrane.Time.vm_time()}
    actions = [buffer: {:output, %Buffer{payload: packet, metadata: metadata}}]

    {actions, state}
  end

  @impl true
  def handle_info({:media_packet, _packet}, _context, state) do
    {[], state}
  end

  @impl true
  def handle_info(_other, _context, state) do
    {[], state}
  end
end
