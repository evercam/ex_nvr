defmodule ExNVR.Elements.RTSP.Source do
  @moduledoc """
  Element that starts an RTSP session and read packets from the same connection
  """

  use Membrane.Source
  use Bunch.Access

  require Membrane.Logger

  alias ExNVR.Elements.RTSP.ConnectionManager
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
    do_handle_setup(state)
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
  def handle_info({:media_packet, _packet}, _ctx, state) do
    {[], state}
  end

  # Received when the rtsp connection failed to receive media packets for
  # a certain duration or the connection closed
  @impl true
  def handle_info({:rtsp_connection_lost, reason}, _ctx, state) do
    Membrane.Logger.warn("RTSP connection lost due to #{reason}, reconnecting ...")
    ConnectionManager.reconnect(state.connection_manager)

    {[event: {:output, %Membrane.Event.Discontinuity{}}], state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, _ctx, %{connection_manager: pid} = state) do
    Membrane.Logger.warn("connection manager exited due to #{inspect(reason)}, reconnect ...")
    do_handle_setup(state)
  end

  @impl true
  def handle_info(_other, _context, state) do
    {[], state}
  end

  defp do_handle_setup(state) do
    {:ok, connection_manager} =
      ConnectionManager.start(
        endpoint: self(),
        stream_uri: state[:stream_uri],
        max_reconnect_attempts: @max_reconnect_attempts,
        reconnect_delay: @reconnect_delay
      )

    Process.monitor(connection_manager)

    {[], %{state | connection_manager: connection_manager}}
  end
end
